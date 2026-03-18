import os
import re
import subprocess
from pathlib import Path

# Paths
PROJECT_DIR = Path(__file__).parent.resolve()
JS_FILE = PROJECT_DIR / "WEB_EXPORT" / "2.5D window V3.js"
EXPORT_PATH = PROJECT_DIR / "WEB_EXPORT" / "2.5D window V3.html"
GODOT_EXE = r"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

print("========================================")
print("> Godot Web App Javascript Patcher")
print("========================================\n")

print("Step 1: Applying iOS & Safari HTTP Bypasses...")

if not JS_FILE.exists():
    print(f"X Cannot find Javascript engine file at {JS_FILE}")
    print("Make sure you Exported from Godot first!")
    exit(1)

with open(JS_FILE, 'r', encoding='utf-8') as f:
    content = f.read()

original_len = len(content)

# Patch 1: Bypass isSecureContext Check
# Find the specific missing.push array addition and disable it.
# We make whitespace and quotes flexible in case Godot's minifier changes them.
secure_context_pattern = r"if\s*\(!Features\.isSecureContext\(\)\)\s*\{\s*missing\.push\(['\"]Secure Context - Check web server configuration \(use HTTPS\)['\"]\);\s*\}"
content, num_subs1 = re.subn(secure_context_pattern, r"/* Bypassed Secure Context Check */", content)

if num_subs1 > 0:
    print("  -> Successfully patched `isSecureContext` block.")
elif "/* Bypassed Secure Context Check */" in content:
    print("  -> `isSecureContext` block is already patched.")
else:
    print("  ! Could not find the exactly formatted `isSecureContext` block to patch. It may already be patched or Godot minified it differently.")

# Patch 2: Bypass AudioWorklet initialization (The iOS RAM/HTTP crash)
# This dynamically finds whatever variable Godot named the audio context and adds a null-safety check to the promise.
# We use ([a-zA-Z0-9_.]+) instead of (.*?) to ensure we don't accidentally match and corrupt an already patched file!
audio_worklet_pattern = r"GodotAudio\.audioPositionWorkletPromise\s*=\s*([a-zA-Z0-9_.]+)\.addModule\((.*?)\);"
content, num_subs2 = re.subn(audio_worklet_pattern, r"GodotAudio.audioPositionWorkletPromise = \1 ? \1.addModule(\2) : Promise.resolve();", content)

if num_subs2 > 0:
    print("  -> Successfully injected AudioWorklet HTTP safety fallback.")
elif "? Promise.resolve()" in content or ": Promise.resolve()" in content:
    print("  -> AudioWorklet is already safely patched.")
else:
    print("  ! Could not find AudioWorklet initialization. It may already be patched or the regex failed on this minification.")

if original_len == len(content) and num_subs1 == 0 and num_subs2 == 0:
    print("  -> No files needed patching. They might already be modified.")
else:
    with open(JS_FILE, 'w', encoding='utf-8') as f:
        f.write(content)
    print("-> Javascript Patches written to disk!")

print("\nStep 2: Injecting iOS Safari Native Input Workaround...")
if EXPORT_PATH.exists():
    with open(EXPORT_PATH, 'r', encoding='utf-8') as f:
        html_content = f.read()

    render_scale_helper_pattern = r"\s*<script>\s*// Per-device web render scale override for weak mobile clients\..*?window\.resetGodotRenderScale.*?</script>\s*"
    html_content, removed_render_scale_helpers = re.subn(render_scale_helper_pattern, "\n", html_content, count=1, flags=re.S)
    if removed_render_scale_helpers > 0:
        print("  -> Removed legacy browser-wide render scale helper from HTML.")

    if "window.promptScreenSize" not in html_content:
        # Inject standard JS prompt at the bottom of the body
        injection = """
        <script>
            // Native UI fallback designed specifically to conquer the iOS Safari WebGL virtual keyboard bug!
            window.promptScreenSize = function(dimensionName) {
                return window.prompt("Enter the physical " + dimensionName + " of THIS screen (in inches):", "0.0");
            };
        </script>
        """
        html_content = html_content.replace('</body>', injection + '\n</body>')
        print("  -> Successfully injected native window.prompt() fallback into HTML.")
    else:
        print("  -> Native UI fallback is already injected into the HTML.")

    if "window.enableWakeLock" not in html_content:
        wake_lock_injection = """
        <script>
            // Best-effort mobile wake lock so calibration/scan screens do not dim out mid-session.
            window.__godotWakeLock = null;
            window.enableWakeLock = async function () {
                if (!('wakeLock' in navigator) || document.hidden) {
                    return false;
                }
                try {
                    if (window.__godotWakeLock) {
                        return true;
                    }
                    window.__godotWakeLock = await navigator.wakeLock.request('screen');
                    window.__godotWakeLock.addEventListener('release', function () {
                        window.__godotWakeLock = null;
                    });
                    return true;
                } catch (err) {
                    console.warn('Wake lock request failed:', err);
                    return false;
                }
            };

            window.disableWakeLock = async function () {
                if (window.__godotWakeLock) {
                    await window.__godotWakeLock.release();
                    window.__godotWakeLock = null;
                }
            };

            document.addEventListener('visibilitychange', function () {
                if (!document.hidden) {
                    window.enableWakeLock();
                }
            });

            ['click', 'touchend', 'keydown'].forEach(function (eventName) {
                window.addEventListener(eventName, function () {
                    window.enableWakeLock();
                }, { passive: true });
            });

            window.addEventListener('load', function () {
                window.enableWakeLock();
            });
        </script>
        """
        html_content = html_content.replace('</body>', wake_lock_injection + '\n</body>')
        print("  -> Successfully injected best-effort screen wake lock helper into HTML.")
    else:
        print("  -> Screen wake lock helper is already injected into the HTML.")

    with open(EXPORT_PATH, 'w', encoding='utf-8') as f:
        f.write(html_content)
else:
    print(f"  ! Could not find the HTML Export file at {EXPORT_PATH}")


print("\n========================================")
print("-> All Done! ")
print("You can now safely run `python serve_godot.py` to play!")
print("========================================")
