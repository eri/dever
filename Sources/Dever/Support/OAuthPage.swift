import Foundation

/// The page the browser lands on after a sign-in, served by the local callback server.
/// Self-contained (no network): the mark, the app's ground and lime, light and dark.
enum OAuthPage {
    enum Outcome: Equatable { case signedIn, refused, notFound }

    /// "/linear/callback" → "Linear". Nil for a path that names no tool Dever connects.
    static func service(path: String) -> String? {
        switch path.split(separator: "/").first.map(String.init) {
        case "slack": "Slack"
        case "linear": "Linear"
        case "github": "GitHub"
        default: nil
        }
    }

    /// What the provider sent back: an `error` (the user refused, the app is not allowed) is not a sign-in.
    static func outcome(matches: Bool, query: [String: String]) -> Outcome {
        guard matches else { return .notFound }
        return query["error"] == nil ? .signedIn : .refused
    }

    static func html(service: String?, outcome: Outcome) -> String {
        let title: String, detail: String, glyph: String
        switch outcome {
        case .signedIn:
            title = service.map { "\($0) is signed in" } ?? "You're signed in"
            detail = "Go back to Dever, it is finishing the connection. You can close this tab."
            glyph = "<path class=\"draw\" d=\"M6.5 12.5l3.6 3.6L17.5 8.5\"/>"
        case .refused:
            title = service.map { "\($0) was not connected" } ?? "Nothing was connected"
            detail = "The sign-in was cancelled or refused. Go back to Dever to try again."
            glyph = "<path class=\"draw\" d=\"M8 8l8 8M16 8l-8 8\"/>"
        case .notFound:
            title = "Nothing to see here"
            detail = "This address only answers while Dever is signing you in."
            glyph = "<path class=\"draw\" d=\"M12 7v6M12 16.6v.4\"/>"
        }
        let tone = outcome == .signedIn ? "ok" : "quiet"
        // The Keychain line only when there is a token to speak of.
        let foot = outcome == .signedIn ? """
        <div class="foot"><svg viewBox="0 0 16 16" aria-hidden="true"><path d="M8 1.5a3.5 3.5 0 0 0-3.5 3.5v2H4a1.5 1.5 0 0 0-1.5 1.5v4.5A1.5 1.5 0 0 0 4 14.5h8a1.5 1.5 0 0 0 1.5-1.5V8.500A1.5 1.5 0 0 0 12 7h-.5V5A3.5 3.5 0 0 0 8 1.500Zm2 5.500H6V5a2 2 0 1 1 4 0v2Z"/></svg>Your token stays in this Mac's Keychain</div>
        """ : ""
        return """
        <!doctype html>
        <html lang="en">
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>Dever</title>
        <style>
        :root { --ground:#F4F4F2; --surface:#FFFFFF; --ink:#111111; --muted:#5F6368; --lime:#3F6212; --lime-ink:#FFFFFF; --edge:#E4E4E0; --wash:rgba(63,98,18,.10); }
        @media (prefers-color-scheme: dark) {
          :root { --ground:#0F0F0F; --surface:#1A1A1A; --ink:#FFFFFF; --muted:#8F8F8F; --lime:#DAFA9C; --lime-ink:#0F0F0F; --edge:#2A2A2A; --wash:rgba(218,250,156,.10); }
        }
        * { box-sizing:border-box; }
        html, body { height:100%; margin:0; }
        body { background:var(--ground); color:var(--ink); font:16px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
          -webkit-font-smoothing:antialiased; display:grid; place-items:center; padding:24px; overflow:hidden; }
        .glow { position:fixed; inset:auto 0 -45vh 0; height:90vh; background:radial-gradient(closest-side, var(--wash), transparent); pointer-events:none; }
        main { position:relative; width:100%; max-width:420px; text-align:center; animation:rise .5s cubic-bezier(.2,.8,.2,1) both; }
        .stage { position:relative; width:96px; height:96px; margin:0 auto 28px; }
        .mark { width:96px; height:96px; display:block; fill:var(--lime); }
        .eye { transform-origin:43px 23px; animation:blink 4.5s 1.2s infinite; }
        .badge { position:absolute; right:-10px; bottom:-10px; width:40px; height:40px; border-radius:50%; background:var(--ink); border:4px solid var(--ground);
          display:grid; place-items:center; animation:pop .45s .35s cubic-bezier(.3,1.5,.5,1) both; }
        .badge.ok { background:var(--lime); }
        .badge svg { width:22px; height:22px; fill:none; stroke:var(--ground); stroke-width:2.6; stroke-linecap:round; stroke-linejoin:round; }
        .badge.ok svg { stroke:var(--lime-ink); }
        .draw { stroke-dasharray:30; stroke-dashoffset:30; animation:draw .4s .6s ease-out forwards; }
        h1 { font-size:30px; line-height:1.15; letter-spacing:-.03em; font-weight:650; margin:0 0 10px; }
        p { margin:0 auto; max-width:330px; color:var(--muted); }
        .foot { margin-top:36px; display:inline-flex; align-items:center; gap:8px; padding:7px 14px 7px 10px; border-radius:999px; background:var(--surface);
          border:1px solid var(--edge); color:var(--muted); font-size:13px; }
        .foot svg { width:14px; height:14px; fill:var(--lime); }
        @keyframes rise { from { opacity:0; transform:translateY(10px); } }
        @keyframes pop { from { opacity:0; transform:scale(.4); } }
        @keyframes draw { to { stroke-dashoffset:0; } }
        @keyframes blink { 0%, 92%, 100% { transform:scaleY(1); } 96% { transform:scaleY(.12); } }
        @media (prefers-reduced-motion: reduce) { *, .draw { animation:none !important; } .draw { stroke-dashoffset:0; } }
        </style>
        <body>
        <div class="glow" aria-hidden="true"></div>
        <main>
          <div class="stage" aria-hidden="true">
            <svg class="mark" viewBox="0 0 64 64">
              <defs><mask id="eye"><rect width="64" height="64" fill="#fff"/><circle class="eye" cx="43" cy="23" r="8" fill="#000"/></mask></defs>
              <path mask="url(#eye)" d="M14 4h18a28 28 0 0 1 0 56H14A10 10 0 0 1 4 50V14A10 10 0 0 1 14 4Z"/>
            </svg>
            <div class="badge \(tone)"><svg viewBox="0 0 24 24">\(glyph)</svg></div>
          </div>
          <h1>\(title)</h1>
          <p>\(detail)</p>
          \(foot)
        </main>
        <script>history.replaceState(null, "", location.pathname)</script>
        </body>
        </html>
        """
    }
}
