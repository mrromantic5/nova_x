package com.tlyfe.nova_x.capture

import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.projection.MediaProjection
import android.os.Bundle
import android.os.SystemClock
import android.view.Surface
import java.io.File
import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Final video parameters, after checking what this phone's encoder supports. */
data class VideoSpec(val width: Int, val height: Int, val fps: Int, val bitrate: Int, val dpi: Int)

/**
 * One screen recording: MediaProjection → VirtualDisplay → H.264 encoder
 * (hardware when available, fed through its input Surface — no frame copies)
 * and, optionally, AAC audio → MP4 (MediaMuxer) in app-private storage.
 *
 * Pause is real: the VirtualDisplay is detached from the encoder, the encoder
 * input is suspended, the microphone is stopped, and every timestamp after a
 * pause is shifted back by the paused time — so the saved video plays straight
 * through with no frozen or skipped section. Anything produced during a pause
 * is dropped.
 *
 * Threads: one for video output, one for audio, one to finalize. The muxer is
 * guarded by [lock]. Callbacks to [listener] come from background threads.
 */
class ScreenRecorderEngine(
    private val projection: MediaProjection,
    private val spec: VideoSpec,
    private val audio: CaptureAudioSource?,
    private val outFile: File,
    private val listener: Listener,
) {
    interface Listener {
        /** The file is complete and playable. [durationUs] excludes pauses. */
        fun onFinished(file: File, durationUs: Long, interrupted: Boolean)
        fun onFailed(code: String, message: String)
        fun onWarning(message: String)
    }

    companion object {
        const val MIME_AVC = MediaFormat.MIMETYPE_VIDEO_AVC
        const val MIME_AAC = MediaFormat.MIMETYPE_AUDIO_AAC
        private const val TIMEOUT_US = 10_000L
        private const val EOS_WAIT_MS = 3_000L

        private fun avcCapabilities(): MediaCodecInfo.VideoCapabilities? = try {
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
                .filter { it.isEncoder && it.supportedTypes.any { t -> t.equals(MIME_AVC, true) } }
                .sortedBy { if (it.name.startsWith("OMX.google.") || it.name.startsWith("c2.android.")) 1 else 0 }
                .firstOrNull()
                ?.getCapabilitiesForType(MIME_AVC)?.videoCapabilities
        } catch (e: Exception) {
            null
        }

        private fun align16(v: Int) = max(16, v - (v % 16))

        /**
         * Picks a size/frame rate/bit rate this phone can encode, starting from
         * the user's choice and stepping down (1080 → 720 → 480) if needed.
         */
        fun choose(realW: Int, realH: Int, dpi: Int, cfg: RecordingConfig, portraitNow: Boolean): VideoSpec {
            var w0 = realW
            var h0 = realH
            val wantPortrait = when (cfg.orientation) {
                "portrait" -> true
                "landscape" -> false
                else -> portraitNow
            }
            if ((h0 >= w0) != wantPortrait) { val t = w0; w0 = h0; h0 = t }
            val shortSide = min(w0, h0)
            val tiers = listOf(1080, 720, 480).let { all ->
                val first = cfg.resolution.toIntOrNull() ?: min(shortSide, 1080)
                listOf(first) + all.filter { it < first }
            }
            val caps = avcCapabilities()
            for (tier in tiers) {
                val scale = min(1.0, tier.toDouble() / shortSide)
                val w = align16((w0 * scale).roundToInt())
                val h = align16((h0 * scale).roundToInt())
                if (caps != null && !caps.isSizeSupported(w, h)) continue
                var fps = cfg.fps
                if (caps != null) {
                    val maxFps = try { caps.getSupportedFrameRatesFor(w, h).upper.toInt() } catch (e: Exception) { 30 }
                    fps = min(fps, max(15, maxFps))
                }
                val bpp = when (cfg.bitrate) { "low" -> 0.05; "medium" -> 0.1; "high" -> 0.18; else -> 0.09 }
                var bitrate = (w.toDouble() * h * fps * bpp).toInt().coerceIn(1_000_000, 24_000_000)
                if (caps != null) bitrate = caps.bitrateRange.clamp(bitrate)
                return VideoSpec(w, h, fps, bitrate, dpi)
            }
            // Nothing matched the reported capabilities: a conservative size most encoders accept.
            val portrait = wantPortrait
            return VideoSpec(if (portrait) 720 else 1280, if (portrait) 1280 else 720, 30, 4_000_000, dpi)
        }
    }

    private val lock = Any()
    private var muxer: MediaMuxer? = null
    @Volatile private var muxerStarted = false
    @Volatile private var expectedTracks = 1
    private var addedTracks = 0
    @Volatile private var videoTrack = -1
    private var audioTrack = -1

    private var videoCodec: MediaCodec? = null
    private var audioCodec: MediaCodec? = null
    private var inputSurface: Surface? = null
    private var display: VirtualDisplay? = null
    private var videoThread: Thread? = null
    private var audioThread: Thread? = null

    @Volatile private var stopping = false
    @Volatile private var cancelled = false
    @Volatile private var paused = false
    @Volatile private var fatal: String? = null
    @Volatile private var finishing = false

    /** Paused intervals in the encoder's clock (System.nanoTime / 1000). */
    private val timeline = PauseTimeline()
    private var firstPtsUs = -1L
    private val lastPts = longArrayOf(-1L, -1L)
    private var sawVideoKey = false
    private var videoSamples = 0
    private var lastWrittenUs = 0L

    private fun nowUs() = System.nanoTime() / 1000

    /** Prepares encoders, muxer and the VirtualDisplay. Throws on failure (caller cleans up via [cancel]). */
    fun start() {
        val format = MediaFormat.createVideoFormat(MIME_AVC, spec.width, spec.height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, spec.bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, spec.fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            // A still screen sends no new frames; repeat the last one so the video keeps time.
            setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, 200_000L)
        }
        val vc = MediaCodec.createEncoderByType(MIME_AVC)
        videoCodec = vc
        vc.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        inputSurface = vc.createInputSurface()
        vc.start()

        if (audio != null) {
            val af = MediaFormat.createAudioFormat(MIME_AAC, CaptureAudioSource.SAMPLE_RATE, 1).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, 128_000)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, CaptureAudioSource.CHUNK_BYTES * 2)
            }
            try {
                val ac = MediaCodec.createEncoderByType(MIME_AAC)
                ac.configure(af, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                ac.start()
                audioCodec = ac
                expectedTracks = 2
            } catch (e: Exception) {
                audioCodec = null
                audio.release()
                listener.onWarning("Audio couldn't be recorded on this phone, so the video has no sound.")
            }
        }

        muxer = MediaMuxer(outFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

        display = projection.createVirtualDisplay(
            "NOVA X screen recording", spec.width, spec.height, spec.dpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, inputSurface, null, null,
        )

        videoThread = Thread({ videoLoop() }, "nova-rec-video").also { it.start() }
        if (audioCodec != null && audio != null) {
            audioThread = Thread({ audioLoop(audio) }, "nova-rec-audio").also { it.start() }
        }
    }

    // ── Controls (main thread) ───────────────────────────────────────────────

    fun pause() {
        if (paused || stopping) return
        timeline.pause(nowUs())
        paused = true
        try { display?.surface = null } catch (e: Exception) { }
        setSuspended(true)
    }

    fun resume() {
        if (!paused || stopping) return
        timeline.resume(nowUs())
        try { display?.surface = inputSurface } catch (e: Exception) { }
        setSuspended(false)
        requestKeyFrame()
        paused = false
    }

    /** Ends the recording and finalizes the file (reported to [listener]). */
    fun stop() {
        if (stopping) return
        if (paused) {
            timeline.resume(nowUs())
            setSuspended(false)
            paused = false
        }
        stopping = true
        finishAsync(deleteFile = false)
    }

    /** Ends without saving; the temporary file is deleted. */
    fun cancel() {
        cancelled = true
        stopping = true
        finishAsync(deleteFile = true)
    }

    private fun setSuspended(on: Boolean) {
        try {
            videoCodec?.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_SUSPEND, if (on) 1 else 0) })
        } catch (e: Exception) { }
    }

    private fun requestKeyFrame() {
        try {
            videoCodec?.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) })
        } catch (e: Exception) { }
    }

    // ── Muxer ────────────────────────────────────────────────────────────────

    private fun addTrack(format: MediaFormat, isVideo: Boolean) {
        synchronized(lock) {
            val m = muxer ?: return
            if (muxerStarted) return // audio given up on after the muxer started
            val t = m.addTrack(format)
            if (isVideo) videoTrack = t else audioTrack = t
            addedTracks++
            if (addedTracks >= expectedTracks) {
                m.start()
                muxerStarted = true
            }
        }
        if (muxerStarted) requestKeyFrame()
    }

    /** Audio failed before the muxer started: carry on with video only. */
    private fun dropAudioTrack() {
        synchronized(lock) {
            if (muxerStarted) return
            expectedTracks = 1
            if (videoTrack >= 0 && addedTracks >= 1) {
                muxer?.start()
                muxerStarted = true
            }
        }
        requestKeyFrame()
    }

    private fun write(isVideo: Boolean, buf: ByteBuffer, info: MediaCodec.BufferInfo) {
        synchronized(lock) {
            val m = muxer ?: return
            if (!muxerStarted) return
            val track = if (isVideo) videoTrack else audioTrack
            if (track < 0) return
            if (isVideo && !sawVideoKey) {
                if (info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME == 0) return
                sawVideoKey = true
            }
            if (!isVideo && !sawVideoKey) return // the file starts at the first video frame
            var pts = timeline.map(info.presentationTimeUs)
            if (pts < 0) return
            if (firstPtsUs < 0) firstPtsUs = pts
            pts -= firstPtsUs
            if (pts < 0) return
            val ti = if (isVideo) 0 else 1
            if (pts <= lastPts[ti]) pts = lastPts[ti] + 1
            lastPts[ti] = pts
            val out = MediaCodec.BufferInfo()
            out.set(info.offset, info.size, pts, info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM.inv())
            buf.position(info.offset)
            buf.limit(info.offset + info.size)
            m.writeSampleData(track, buf, out)
            if (isVideo) videoSamples++
            if (pts > lastWrittenUs) lastWrittenUs = pts
        }
    }

    // ── Video ────────────────────────────────────────────────────────────────

    private fun videoLoop() {
        val codec = videoCodec ?: return
        val info = MediaCodec.BufferInfo()
        var eosSent = false
        var eosAt = 0L
        val startedAt = SystemClock.elapsedRealtime()
        var audioWatchdog = expectedTracks == 2
        try {
            while (!cancelled) {
                // Audio never produced anything: don't hold the video back.
                if (audioWatchdog && SystemClock.elapsedRealtime() - startedAt > 3_000) {
                    audioWatchdog = false
                    if (!muxerStarted && videoTrack >= 0) {
                        dropAudioTrack()
                        listener.onWarning("Audio couldn't be recorded on this phone, so the video has no sound.")
                    }
                }
                if (stopping && !eosSent) {
                    try { codec.signalEndOfInputStream() } catch (e: Exception) { }
                    eosSent = true
                    eosAt = SystemClock.elapsedRealtime()
                }
                val idx = codec.dequeueOutputBuffer(info, TIMEOUT_US)
                when {
                    idx == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                        if (eosSent && SystemClock.elapsedRealtime() - eosAt > EOS_WAIT_MS) break
                    }
                    idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> addTrack(codec.outputFormat, true)
                    idx >= 0 -> {
                        val buf = codec.getOutputBuffer(idx)
                        if (buf != null && info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                            write(true, buf, info)
                        }
                        codec.releaseOutputBuffer(idx, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                    }
                }
            }
        } catch (e: Exception) {
            fail(CaptureContract.E_ENCODER, "The video encoder stopped unexpectedly.")
        }
    }

    // ── Audio ────────────────────────────────────────────────────────────────

    private fun audioLoop(src: CaptureAudioSource) {
        val codec = audioCodec ?: return
        val chunk = ByteArray(CaptureAudioSource.CHUNK_BYTES)
        val info = MediaCodec.BufferInfo()
        var micOff = false
        var formatSeen = false
        try {
            src.start()
            while (!stopping && !cancelled) {
                if (paused) {
                    if (!micOff) { src.stop(); micOff = true }
                    formatSeen = drainAudio(codec, info, formatSeen)
                    try { Thread.sleep(20) } catch (e: InterruptedException) { break }
                    continue
                }
                if (micOff) { src.start(); micOff = false }
                val n = src.read(chunk)
                if (n < 0) {
                    listener.onWarning("Audio stopped part-way through, so the rest of the video has no sound.")
                    break
                }
                if (n > 0) {
                    val samples = n / 2
                    val pts = nowUs() - samples * 1_000_000L / CaptureAudioSource.SAMPLE_RATE
                    queueAudio(codec, chunk, n, pts, false)
                }
                formatSeen = drainAudio(codec, info, formatSeen)
            }
            src.stop()
            queueAudio(codec, chunk, 0, nowUs(), true)
            val end = SystemClock.elapsedRealtime() + 2_000
            while (!cancelled && SystemClock.elapsedRealtime() < end) {
                val idx = codec.dequeueOutputBuffer(info, TIMEOUT_US)
                if (idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    addTrack(codec.outputFormat, false)
                    formatSeen = true
                } else if (idx >= 0) {
                    val buf = codec.getOutputBuffer(idx)
                    if (buf != null && info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) write(false, buf, info)
                    codec.releaseOutputBuffer(idx, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
        } catch (e: Exception) {
            listener.onWarning("Audio stopped part-way through, so the rest of the video has no sound.")
            if (!formatSeen) dropAudioTrack()
        } finally {
            src.release()
        }
        if (!formatSeen) dropAudioTrack()
    }

    private fun queueAudio(codec: MediaCodec, data: ByteArray, size: Int, pts: Long, eos: Boolean) {
        val idx = codec.dequeueInputBuffer(TIMEOUT_US)
        if (idx < 0) return // encoder busy: drop this chunk rather than block the microphone
        val buf = codec.getInputBuffer(idx) ?: return
        buf.clear()
        val n = min(size, buf.remaining())
        if (n > 0) buf.put(data, 0, n)
        codec.queueInputBuffer(idx, 0, n, pts, if (eos) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0)
    }

    /** Writes whatever AAC output is ready. Returns whether the format has been seen. */
    private fun drainAudio(codec: MediaCodec, info: MediaCodec.BufferInfo, formatSeen: Boolean): Boolean {
        var seen = formatSeen
        while (true) {
            val idx = codec.dequeueOutputBuffer(info, 0)
            if (idx == MediaCodec.INFO_TRY_AGAIN_LATER) return seen
            if (idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                addTrack(codec.outputFormat, false)
                seen = true
                continue
            }
            if (idx < 0) continue
            val buf = codec.getOutputBuffer(idx)
            if (buf != null && info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) write(false, buf, info)
            codec.releaseOutputBuffer(idx, false)
        }
    }

    // ── Finish ───────────────────────────────────────────────────────────────

    private fun fail(code: String, message: String) {
        if (fatal == null) fatal = "$code|$message"
        if (!stopping) {
            stopping = true
            finishAsync(deleteFile = false)
        }
    }

    private fun finishAsync(deleteFile: Boolean) {
        synchronized(lock) {
            if (finishing) return
            finishing = true
        }
        Thread({ finish(deleteFile) }, "nova-rec-finish").start()
    }

    private fun finish(deleteFile: Boolean) {
        try { videoThread?.join(EOS_WAIT_MS + 1_500) } catch (e: InterruptedException) { }
        try { audioThread?.join(4_000) } catch (e: InterruptedException) { }
        var finalized = false
        synchronized(lock) {
            val m = muxer
            if (m != null && muxerStarted && videoSamples > 0 && !deleteFile) {
                finalized = try { m.stop(); true } catch (e: Exception) { false }
            }
            try { m?.release() } catch (e: Exception) { }
            muxer = null
        }
        releaseCodecs()
        val samples = videoSamples
        if (deleteFile) {
            outFile.delete()
            return
        }
        val f = fatal
        when {
            finalized && outFile.length() > 0 -> listener.onFinished(outFile, lastWrittenUs, interrupted = f != null)
            samples == 0 && f == null -> {
                outFile.delete()
                listener.onFailed(CaptureContract.E_TOO_SHORT, "The recording was too short to save.")
            }
            else -> {
                outFile.delete()
                val parts = (f ?: "${CaptureContract.E_SAVE}|The video couldn't be finished.").split("|", limit = 2)
                listener.onFailed(parts[0], parts.getOrElse(1) { "The video couldn't be finished." })
            }
        }
    }

    private fun releaseCodecs() {
        try { display?.release() } catch (e: Exception) { }
        display = null
        try { videoCodec?.stop() } catch (e: Exception) { }
        try { videoCodec?.release() } catch (e: Exception) { }
        videoCodec = null
        try { audioCodec?.stop() } catch (e: Exception) { }
        try { audioCodec?.release() } catch (e: Exception) { }
        audioCodec = null
        try { inputSurface?.release() } catch (e: Exception) { }
        inputSurface = null
    }
}
