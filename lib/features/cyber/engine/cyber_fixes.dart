// lib/features/cyber/engine/cyber_fixes.dart
//
// NOVA Cyber — ready-to-paste fixes, per finding and per platform. The
// platform NOVA Cyber detected is shown first.

class FixGuide {
  const FixGuide({required this.steps, this.snippets = const {}, this.verify = ''});
  final List<String> steps;

  /// platform → code. Platforms: nginx, apache, iis, cloudflare, vercel,
  /// netlify, php, express, wordpress, any.
  final Map<String, String> snippets;

  /// How to confirm it's fixed.
  final String verify;
}

const Map<String, String> platformLabels = {
  'nginx': 'Nginx',
  'apache': 'Apache / .htaccess',
  'litespeed': 'LiteSpeed / .htaccess',
  'iis': 'IIS (web.config)',
  'cloudflare': 'Cloudflare',
  'vercel': 'Vercel (vercel.json)',
  'netlify': 'Netlify (_headers)',
  'php': 'PHP',
  'express': 'Node / Express',
  'wordpress': 'WordPress',
  'any': 'General',
};

/// Header-based fix in every server format.
FixGuide _header(String name, String value, {List<String> steps = const [], String verify = ''}) => FixGuide(
      steps: [...steps, 'Add the header below to every HTTPS response, then reload the site and re-check.'],
      verify: verify.isEmpty ? 'Re-check: the response must contain "$name: $value".' : verify,
      snippets: {
        'nginx': '# inside server { … } (443)\nadd_header $name "$value" always;',
        'apache': '# .htaccess or <VirtualHost *:443>\n<IfModule mod_headers.c>\n  Header always set $name "${value.replaceAll('"', '\\"')}"\n</IfModule>',
        'litespeed': '<IfModule mod_headers.c>\n  Header always set $name "${value.replaceAll('"', '\\"')}"\n</IfModule>',
        'iis': '<system.webServer>\n  <httpProtocol>\n    <customHeaders>\n      <add name="$name" value="${value.replaceAll('"', '&quot;')}" />\n    </customHeaders>\n  </httpProtocol>\n</system.webServer>',
        'cloudflare': 'Rules › Transform Rules › Modify Response Header › Create rule\n  Set static  $name = $value',
        'vercel': '{\n  "headers": [\n    { "source": "/(.*)", "headers": [ { "key": "$name", "value": "${value.replaceAll('"', '\\"')}" } ] }\n  ]\n}',
        'netlify': '# _headers\n/*\n  $name: $value',
        'php': '<?php\nheader(\'$name: ${value.replaceAll("'", "\\'")}\');',
        'express': '// npm i helmet  (sets this and other headers)\napp.use((req, res, next) => {\n  res.setHeader(\'$name\', \'${value.replaceAll("'", "\\'")}\');\n  next();\n});',
      },
    );

FixGuide _block(String what, String pattern, String apacheMatch, {List<String> steps = const []}) => FixGuide(
      steps: [
        'Delete $what from the public web folder (and rotate any password or key it contained — assume it was copied).',
        ...steps,
        'Block the pattern in the server so a future deploy can\'t expose it again.',
      ],
      verify: 'Re-check: the path must answer 403 or 404.',
      snippets: {
        'nginx': 'location ~ $pattern {\n  deny all;\n  return 404;\n}',
        'apache': '<FilesMatch "$apacheMatch">\n  Require all denied\n</FilesMatch>\nRedirectMatch 404 $pattern',
        'litespeed': '<FilesMatch "$apacheMatch">\n  Require all denied\n</FilesMatch>',
        'iis': '<security>\n  <requestFiltering>\n    <hiddenSegments>\n      <add segment="${what.replaceAll('/', '')}" />\n    </hiddenSegments>\n  </requestFiltering>\n</security>',
        'cloudflare': 'Security › WAF › Custom rules › Create rule\n  (http.request.uri.path matches "$pattern")  →  Block',
        'any': 'Keep secrets and backups OUTSIDE the web root (e.g. /home/app/config, not /public_html).',
      },
    );

final Map<String, FixGuide> fixes = {
  // Transport
  'tls.none': const FixGuide(steps: [
    'Get a free certificate from Let\'s Encrypt (most hosts: "SSL/TLS" → "AutoSSL" or "Let\'s Encrypt").',
    'Redirect every http:// URL to https:// with a 301.',
    'Then add HSTS.',
  ], snippets: {
    'nginx': 'sudo certbot --nginx -d example.com -d www.example.com',
    'apache': 'sudo certbot --apache -d example.com -d www.example.com',
    'cloudflare': 'SSL/TLS › Overview › Full (strict)\nSSL/TLS › Edge Certificates › Always Use HTTPS: On',
  }),
  'tls.cert.expired': const FixGuide(steps: ['Renew the certificate now.', 'Make renewal automatic and test it.'], snippets: {
    'nginx': 'sudo certbot renew && sudo systemctl reload nginx\nsudo certbot renew --dry-run   # test automatic renewal',
    'apache': 'sudo certbot renew && sudo systemctl reload apache2',
  }),
  'tls.cert.expiring': const FixGuide(steps: ['Renew before expiry and confirm the renewal timer runs.'], snippets: {
    'nginx': 'sudo certbot renew --dry-run\nsystemctl list-timers | grep certbot',
  }),
  'tls.redirect': const FixGuide(steps: ['Redirect all plain-HTTP requests to HTTPS with a permanent (301) redirect.'], verify: 'Re-check: http:// must answer 301 to https://.', snippets: {
    'nginx': 'server {\n  listen 80;\n  server_name example.com www.example.com;\n  return 301 https://\$host\$request_uri;\n}',
    'apache': 'RewriteEngine On\nRewriteCond %{HTTPS} off\nRewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]',
    'cloudflare': 'SSL/TLS › Edge Certificates › Always Use HTTPS: On',
    'iis': '<rewrite><rules>\n  <rule name="HTTPS" stopProcessing="true">\n    <match url="(.*)" />\n    <conditions><add input="{HTTPS}" pattern="off" /></conditions>\n    <action type="Redirect" url="https://{HTTP_HOST}/{R:1}" redirectType="Permanent" />\n  </rule>\n</rules></rewrite>',
    'express': 'app.use((req, res, next) => req.secure ? next() : res.redirect(301, `https://\${req.headers.host}\${req.url}`));',
  }),
  'hdr.hsts': _header('Strict-Transport-Security', 'max-age=31536000; includeSubDomains',
      steps: ['Make sure every subdomain works over HTTPS first (includeSubDomains applies to all of them).']),
  'hdr.hsts.short': _header('Strict-Transport-Security', 'max-age=31536000; includeSubDomains'),
  'hdr.hsts.subdomains': _header('Strict-Transport-Security', 'max-age=31536000; includeSubDomains'),

  // Headers
  'hdr.csp': _header('Content-Security-Policy',
      "default-src 'self'; script-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'self'; form-action 'self'; upgrade-insecure-requests",
      steps: [
        'Start with Content-Security-Policy-Report-Only to see what would be blocked, then switch to enforcing.',
        "Add each external source you really use (e.g. script-src 'self' https://www.googletagmanager.com).",
        "For inline scripts, use a per-request nonce: script-src 'self' 'nonce-RANDOM' and <script nonce=\"RANDOM\">.",
      ]),
  'hdr.csp.weak': _header('Content-Security-Policy',
      "default-src 'self'; script-src 'self' 'nonce-{RANDOM}' 'strict-dynamic'; object-src 'none'; base-uri 'self'; frame-ancestors 'self'; form-action 'self'",
      steps: [
        "Replace 'unsafe-inline' with a nonce generated for each response (and add it to your <script> tags).",
        'Remove wildcards (*, https:, data:) from script-src.',
        "Add object-src 'none' and base-uri 'self'.",
      ]),
  'hdr.xcto': _header('X-Content-Type-Options', 'nosniff'),
  'hdr.frame': _header('Content-Security-Policy', "frame-ancestors 'self'",
      steps: ['If you already send a CSP, add frame-ancestors \'self\' to it instead of a second header.', 'Also send "X-Frame-Options: SAMEORIGIN" for very old browsers.']),
  'hdr.referrer': _header('Referrer-Policy', 'strict-origin-when-cross-origin'),
  'hdr.permissions': _header('Permissions-Policy', 'camera=(), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=()'),
  'hdr.coop': _header('Cross-Origin-Opener-Policy', 'same-origin'),
  'hdr.xxp': _header('X-XSS-Protection', '0'),

  // Server
  'srv.version': const FixGuide(steps: ['Hide version numbers in every layer.'], snippets: {
    'nginx': '# nginx.conf, http { … }\nserver_tokens off;',
    'apache': '# apache2.conf / httpd.conf\nServerTokens Prod\nServerSignature Off',
    'php': '; php.ini\nexpose_php = Off',
    'express': "app.disable('x-powered-by');",
    'iis': '<security><requestFiltering removeServerHeader="true" /></security>\n<httpProtocol><customHeaders><remove name="X-Powered-By" /></customHeaders></httpProtocol>',
  }),
  'srv.eol.php': const FixGuide(steps: [
    'Check your code with the new version locally (composer update; run tests).',
    'In your host\'s control panel choose PHP 8.3 or newer (cPanel: "MultiPHP Manager" / "Select PHP Version").',
  ], snippets: {
    'any': '# Find code that breaks on PHP 8\ncomposer require --dev phpcompatibility/php-compatibility\nvendor/bin/phpcs -p . --standard=PHPCompatibility --runtime-set testVersion 8.3',
  }),
  'srv.trace': const FixGuide(steps: ['Disable the TRACE method.'], snippets: {
    'apache': 'TraceEnable off',
    'nginx': '# nginx rejects TRACE by default; if a proxy forwards it:\nif (\$request_method = TRACE) { return 405; }',
    'iis': '<security><requestFiltering><verbs><add verb="TRACE" allowed="false" /></verbs></requestFiltering></security>',
  }),
  'srv.methods': const FixGuide(steps: ['Allow only the methods each route needs.'], snippets: {
    'nginx': 'location / {\n  limit_except GET POST HEAD { deny all; }\n}',
    'apache': '<LimitExcept GET POST HEAD>\n  Require all denied\n</LimitExcept>',
  }),

  // Cookies
  'cookie.flags': const FixGuide(steps: [
    'Set Secure, HttpOnly and SameSite on session cookies.',
    'Use the __Host- prefix for the session cookie (forces Secure, Path=/ and no Domain).',
  ], snippets: {
    'php': "<?php\nsession_set_cookie_params([\n  'lifetime' => 0, 'path' => '/', 'secure' => true,\n  'httponly' => true, 'samesite' => 'Lax',\n]);\nsession_name('__Host-sid');\nsession_start();",
    'express': "app.use(session({\n  name: '__Host-sid',\n  cookie: { secure: true, httpOnly: true, sameSite: 'lax', path: '/' },\n  // …\n}));",
    'nginx': '# when a backend can\'t be changed (nginx ≥ 1.19.3)\nproxy_cookie_flags ~ secure httponly samesite=lax;',
    'apache': 'Header always edit Set-Cookie ^(.*)\$ "\$1; Secure; HttpOnly; SameSite=Lax"',
  }),

  // Content
  'content.mixed.active': const FixGuide(steps: ['Change every http:// resource to https://.', 'Add upgrade-insecure-requests to your CSP as a safety net.'],
      snippets: {'any': 'Content-Security-Policy: upgrade-insecure-requests'}),
  'content.mixed.passive': const FixGuide(steps: ['Serve images and media over HTTPS.']),
  'content.sri': const FixGuide(steps: [
    'Pin an exact version of each CDN file and add its integrity hash.',
    'Generate the hash with the command below (or copy it from the CDN\'s "Copy SRI" button).',
  ], snippets: {
    'any': '<script src="https://cdn.example.com/lib@1.2.3/lib.min.js"\n        integrity="sha384-BASE64HASH" crossorigin="anonymous"></script>\n\n# hash:\ncurl -s URL | openssl dgst -sha384 -binary | openssl base64 -A',
  }),
  'content.form.http': const FixGuide(steps: ['Change the form action to https://.']),
  'content.password.http': const FixGuide(steps: ['Serve the whole site over HTTPS.']),
  'content.password.get': const FixGuide(steps: ['Use method="post" for login and any form with secrets.'],
      snippets: {'any': '<form method="post" action="/login">'}),
  'content.secret': const FixGuide(steps: [
    'Revoke the exposed keys in the provider\'s dashboard now and create new ones.',
    'Move secret keys to the server (environment variables) and call the provider from your backend.',
    'For Google browser keys: restrict to HTTP referrers (your domains) and to the APIs you use.',
  ]),
  'content.comments': const FixGuide(steps: ['Remove comments from production HTML (most build tools have an option: minify with removeComments).']),

  // Dependencies
  'dep': const FixGuide(steps: [
    'Update the library to the version shown (or newer) and test.',
    'If it comes from a CDN tag, change the version in the URL and update the integrity hash.',
    'Enable automated updates (Dependabot / Renovate) so this doesn\'t happen again.',
  ], snippets: {
    'any': 'npm install PACKAGE@latest      # npm\ncomposer update vendor/package   # PHP\nnpm audit fix                    # all npm advisories',
  }),
  'dep.angularjs.eol': const FixGuide(steps: ['Plan a migration to a supported framework (Angular, Vue, React).', 'Meanwhile use a strict CSP without \'unsafe-eval\'.']),

  // DNS & email
  'dns.spf': const FixGuide(steps: ['Add one TXT record at the root of the domain listing who sends your email.'], snippets: {
    'any': 'Type: TXT   Name: @\nValue: v=spf1 include:_spf.google.com -all        (Google Workspace)\nValue: v=spf1 include:spf.protection.outlook.com -all   (Microsoft 365)\nValue: v=spf1 -all                               (domain sends no email)',
  }),
  'dns.spf.multiple': const FixGuide(steps: ['Merge all SPF mechanisms into a single v=spf1 record.']),
  'dns.spf.all': const FixGuide(steps: ['Replace +all with -all.']),
  'dns.spf.soft': const FixGuide(steps: ['End the record with -all.']),
  'dns.dmarc': const FixGuide(steps: ['Add a DMARC record; start with quarantine and reports, then move to reject.'], snippets: {
    'any': 'Type: TXT   Name: _dmarc\nValue: v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com; adkim=s; aspf=s',
  }),
  'dns.dmarc.none': const FixGuide(steps: ['Read a few weeks of DMARC reports, then raise the policy.'], snippets: {'any': 'v=DMARC1; p=reject; rua=mailto:dmarc@example.com'}),
  'dns.caa': const FixGuide(steps: ['Add CAA records for the certificate authorities you use.'], snippets: {
    'any': 'Type: CAA   Name: @   Value: 0 issue "letsencrypt.org"\nType: CAA   Name: @   Value: 0 iodef "mailto:security@example.com"',
  }),
  'dns.dnssec': const FixGuide(steps: ['Enable DNSSEC at your DNS provider (Cloudflare: DNS › Settings › DNSSEC).', 'Add the DS record it shows at your domain registrar.']),
  'dns.takeover': const FixGuide(steps: [
    'Delete the dangling DNS record now (this removes the risk immediately).',
    'Or re-create the resource it points to in your own account.',
    'Add "delete DNS" to your checklist whenever you remove a hosted service.',
  ]),

  // Exposure
  'exp.env': _block('.env files', r'/\.env', r'^\.env', steps: ['Rotate every secret that was in the file (database, mail, API keys, APP_KEY).']),
  'exp.git': _block('the .git folder', r'/\.git', r'^\.git', steps: ['Deploy build output only, not the repository.', 'Rotate any secret that was ever committed (it is in the history).']),
  'exp.svn': _block('the .svn folder', r'/\.svn', r'^\.svn'),
  'exp.hg': _block('the .hg folder', r'/\.hg', r'^\.hg'),
  'exp.dsstore': _block('.DS_Store files', r'/\.DS_Store', r'^\.DS_Store$'),
  'exp.configbak': _block('config backups', r'\.(bak|old|orig|save|swp|~)$', r'\.(bak|old|orig|save|swp)$|~$', steps: ['Change the database password and WordPress salts.']),
  'exp.sourcebak': _block('source backups', r'\.(bak|old|orig|save)$', r'\.(bak|old|orig|save)$'),
  'exp.sqldump': _block('database dumps', r'\.(sql|sql\.gz|dump)$', r'\.(sql|gz|dump)$', steps: ['Treat the data as leaked: check for personal data and inform users if required.']),
  'exp.archive': _block('backup archives', r'\.(zip|tar|tar\.gz|tgz|7z|rar)$', r'\.(zip|tar|gz|tgz|7z|rar)$', steps: ['Store backups outside the web root or in private storage.']),
  'exp.phpinfo': _block('phpinfo pages', r'/(phpinfo|info|test)\.php$', r'^(phpinfo|info|test)\.php$'),
  'exp.serverstatus': const FixGuide(steps: ['Allow server-status only from localhost.'], snippets: {
    'apache': '<Location "/server-status">\n  SetHandler server-status\n  Require local\n</Location>',
  }),
  'exp.htpasswd': _block('.htpasswd', r'/\.ht', r'^\.ht', steps: ['Change the passwords in it.']),
  'exp.npmrc': _block('.npmrc', r'/\.npmrc', r'^\.npmrc$', steps: ['Revoke the npm token at npmjs.com › Access Tokens.']),
  'exp.webconfig': const FixGuide(steps: ['IIS hides web.config by default; another server serving this folder needs to deny it.'], snippets: {
    'nginx': 'location ~* /web\\.config\$ { deny all; }',
  }),
  'exp.docker': _block('docker-compose and Dockerfiles', r'/(docker-compose\.ya?ml|Dockerfile)$', r'^(docker-compose\.ya?ml|Dockerfile)$'),
  'exp.aws': _block('cloud credentials', r'/\.aws', r'^\.aws', steps: ['Deactivate the access key in AWS IAM now and review CloudTrail for misuse.']),
  'exp.sshkey': _block('SSH keys', r'/\.ssh', r'^\.ssh', steps: ['Remove the key from every authorized_keys file and create a new key pair.']),
  'exp.manifest': _block('dependency manifests', r'/(composer\.(json|lock)|package(-lock)?\.json|yarn\.lock)$', r'^(composer\.(json|lock)|package(-lock)?\.json|yarn\.lock)$'),
  'exp.logs': _block('log files', r'\.log$|/error_log$', r'\.log$|^error_log$', steps: ['Write logs outside the web root (Laravel: storage/ must not be public).']),
  'exp.debug': const FixGuide(steps: [
    'Turn debug tools off in production (APP_DEBUG=false, remove Telescope/Debugbar/profiler from production builds).',
    'Spring Boot: expose only health/info: management.endpoints.web.exposure.include=health,info',
  ]),
  'exp.listing': const FixGuide(steps: ['Disable automatic directory indexes.'], snippets: {
    'apache': 'Options -Indexes',
    'nginx': 'autoindex off;',
    'iis': '<directoryBrowse enabled="false" />',
  }),
  'exp.sourcemap': const FixGuide(steps: ['Don\'t publish .map files; upload them privately to your error tracker if needed.'], snippets: {
    'any': '// vite.config.js\nexport default { build: { sourcemap: false } }\n\n// webpack\ndevtool: false',
    'nginx': 'location ~* \\.map\$ { deny all; }',
  }),

  // Access
  'access.dbadmin': const FixGuide(steps: ['Remove phpMyAdmin/Adminer from the public site, or restrict it to your IP.'], snippets: {
    'nginx': 'location /phpmyadmin {\n  allow 203.0.113.10;   # your IP\n  deny all;\n}',
    'apache': '<Location /phpmyadmin>\n  Require ip 203.0.113.10\n</Location>',
  }),
  'access.adminlogin': const FixGuide(steps: ['Turn on 2FA for every admin account.', 'Limit login attempts.', 'Restrict admin paths by IP if your team has fixed IPs.']),
  'access.cors.reflect': const FixGuide(steps: ['Replace origin reflection with a fixed allow-list.'], snippets: {
    'express': "const allowed = new Set(['https://example.com', 'https://app.example.com']);\napp.use(cors({ origin: (o, cb) => cb(null, !o || allowed.has(o)), credentials: true }));",
    'php': "<?php\n\$allowed = ['https://example.com', 'https://app.example.com'];\n\$o = \$_SERVER['HTTP_ORIGIN'] ?? '';\nif (in_array(\$o, \$allowed, true)) {\n  header('Access-Control-Allow-Origin: ' . \$o);\n  header('Vary: Origin');\n}",
    'nginx': 'map \$http_origin \$cors_ok {\n  default "";\n  "https://example.com" \$http_origin;\n}\nadd_header Access-Control-Allow-Origin \$cors_ok always;\nadd_header Vary Origin always;',
  }),
  'access.cors.null': const FixGuide(steps: ['Remove "null" from the allowed origins.']),
  'access.hostheader': const FixGuide(steps: ['Build absolute URLs from configuration, never from request headers.', 'Ignore X-Forwarded-Host unless it comes from your own proxy.'], snippets: {
    'php': "// Laravel: config/app.php 'url' => env('APP_URL') and TrustProxies only for your proxy IPs",
    'express': "app.set('trust proxy', 'loopback'); // only your own proxy",
    'nginx': 'proxy_set_header X-Forwarded-Host \$host;   # overwrite whatever the client sent',
  }),
  'access.redirect.open': const FixGuide(steps: ['Accept only relative paths (starting with a single "/") or a fixed list of hosts.'], snippets: {
    'php': "<?php\n\$to = \$_GET['next'] ?? '/';\nif (!preg_match('#^/(?!/)#', \$to)) \$to = '/';\nheader('Location: ' . \$to);",
    'express': "const next = String(req.query.next || '/');\nres.redirect(/^\\/(?!\\/)/.test(next) ? next : '/');",
  }),
  'access.login.ratelimit': const FixGuide(steps: ['Limit failed logins per account and per IP.', 'Show a CAPTCHA after a few failures.', 'Offer 2FA.'], snippets: {
    'nginx': 'limit_req_zone \$binary_remote_addr zone=login:10m rate=5r/m;\nlocation = /login { limit_req zone=login burst=5 nodelay; proxy_pass http://app; }',
    'express': "import rateLimit from 'express-rate-limit';\napp.post('/login', rateLimit({ windowMs: 15 * 60 * 1000, limit: 5 }), loginHandler);",
    'wordpress': 'Install a login-limit plugin (e.g. Limit Login Attempts Reloaded) and enable 2FA.',
    'cloudflare': 'Security › WAF › Rate limiting rules › path equals /login → 5 requests / 1 minute → Block',
  }),
  'api.graphql.introspection': const FixGuide(steps: ['Disable introspection in production.'], snippets: {
    'express': 'new ApolloServer({ schema, introspection: process.env.NODE_ENV !== "production" })',
  }),
  'api.docs': const FixGuide(steps: ['Protect API docs with authentication or don\'t deploy them to production.']),
  'wp.users': const FixGuide(steps: ['Hide the users endpoint from visitors.'], snippets: {
    'wordpress': "// functions.php\nadd_filter('rest_endpoints', function (\$e) {\n  if (!is_user_logged_in()) {\n    unset(\$e['/wp/v2/users'], \$e['/wp/v2/users/(?P<id>[\\\\d]+)']);\n  }\n  return \$e;\n});",
  }),
  'wp.xmlrpc': const FixGuide(steps: ['Disable XML-RPC if you don\'t use Jetpack or the mobile app.'], snippets: {
    'wordpress': "// functions.php\nadd_filter('xmlrpc_enabled', '__return_false');",
    'apache': '<Files xmlrpc.php>\n  Require all denied\n</Files>',
    'nginx': 'location = /xmlrpc.php { deny all; }',
  }),
  'wp.inventory': const FixGuide(steps: ['Dashboard › Updates: update core and plugins; enable auto-updates; delete unused plugins.']),

  // Injection
  'inj.xss.reflected': const FixGuide(steps: [
    'Encode output for its context. Never insert raw request values into HTML.',
    'Add a strict Content-Security-Policy so a missed spot can\'t run scripts.',
  ], snippets: {
    'php': "<?= htmlspecialchars(\$value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?>",
    'express': '// Use a template engine with auto-escaping (EJS <%= %>, Pug, Handlebars {{ }}),\n// never res.send(`<p>\${req.query.q}</p>`).',
    'any': 'JavaScript: element.textContent = value;   // not innerHTML',
  }),
  'inj.xss.partial': const FixGuide(steps: ['Encode quotes too (ENT_QUOTES).'], snippets: {
    'php': "htmlspecialchars(\$value, ENT_QUOTES, 'UTF-8')",
  }),
  'inj.ssti': const FixGuide(steps: ['Never render user input as a template; pass it as data.'], snippets: {
    'any': '# Wrong:  render_template_string("Hello " + name)\n# Right:  render_template("hello.html", name=name)',
  }),
  'inj.sql.error': const FixGuide(steps: ['Use prepared statements for every query.', 'Turn off database error output to visitors (log them instead).'], snippets: {
    'php': "<?php\n\$st = \$pdo->prepare('SELECT * FROM products WHERE id = ?');\n\$st->execute([\$_GET['id']]);",
    'express': "await db.query('SELECT * FROM products WHERE id = \$1', [req.query.id]);",
  }),
  'inj.sql.expression': const FixGuide(steps: ['Bind parameters and cast numeric IDs to integers before use.'], snippets: {
    'php': "<?php\n\$id = filter_input(INPUT_GET, 'id', FILTER_VALIDATE_INT);\nif (\$id === false || \$id === null) { http_response_code(400); exit; }\n\$st = \$pdo->prepare('SELECT * FROM items WHERE id = ?');\n\$st->execute([\$id]);",
  }),
  'inj.traversal': const FixGuide(steps: ['Map allowed names to files; never concatenate user input into a path.'], snippets: {
    'php': "<?php\n\$pages = ['about' => 'about.php', 'contact' => 'contact.php'];\n\$file = \$pages[\$_GET['page'] ?? ''] ?? 'home.php';\ninclude __DIR__ . '/pages/' . \$file;",
  }),

  // Network
  'net.port': const FixGuide(steps: [
    'Close the port to the internet, or allow only your own IPs.',
    'If the service is only used by your web app, bind it to 127.0.0.1.',
    'Make sure it has a strong password anyway.',
  ], snippets: {
    'any': '# Ubuntu (ufw)\nsudo ufw deny PORT\n\n# MySQL: /etc/mysql/mysql.conf.d/mysqld.cnf\nbind-address = 127.0.0.1\n\n# Redis: /etc/redis/redis.conf\nbind 127.0.0.1 ::1\nprotected-mode yes',
  }),
  'policy.securitytxt': const FixGuide(steps: ['Publish a security.txt file.'], snippets: {
    'any': '# /.well-known/security.txt\nContact: mailto:security@example.com\nExpires: 2027-12-31T23:59:59Z\nPreferred-Languages: en',
  }),
};

/// The guide for a finding id (handles families such as dep.*, net.port.*).
FixGuide? fixFor(String id) {
  if (fixes.containsKey(id)) return fixes[id];
  if (id.startsWith('dep.')) return fixes['dep'];
  if (id.startsWith('net.port.')) return fixes['net.port'];
  if (id.startsWith('code.')) return fixes['content.secret'];
  return null;
}

/// Snippet platforms in display order: the detected platform first.
List<String> orderedPlatforms(FixGuide g, String primary, Set<String> stack) {
  final keys = g.snippets.keys.toList();
  int rank(String k) {
    if (k == primary) return 0;
    if (stack.contains(k)) return 1;
    if (k == 'any') return 2;
    return 3;
  }

  keys.sort((a, b) => rank(a).compareTo(rank(b)));
  return keys;
}
