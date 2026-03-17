-- ohmyvoice: push-to-talk voice input for macOS
--
-- Hammerspoon manages both the daemon process and the hotkey.
-- The daemon MUST be a child of Hammerspoon (a GUI app) so that
-- ffmpeg's AVFoundation audio capture gets a full AudioSession.
-- LaunchAgent lacks this context and produces degraded audio.
--
-- Setup:
--   1. Edit paths and environment below to match your install.
--   2. Copy this into ~/.hammerspoon/init.lua (or require it).
--   3. Grant Hammerspoon Accessibility in System Settings.
--   4. Reload config: menubar icon → Reload Config.
--
-- Hotkey: hold Right Command to record, release to stop.
-- To use a different key, change the keyCode check below.
-- Common keyCodes: 54 = Right Cmd, 55 = Left Cmd, 61 = Right Option.

local nodeBin      = "/opt/homebrew/bin/node"
local projectDir   = os.getenv("HOME") .. "/path-to/ohmyvoice"
local daemonScript = projectDir .. "/dist/daemon.js"
local cliScript    = projectDir .. "/dist/cli.js"

----------------------------------------------------------------
-- Daemon process (managed by Hammerspoon)
----------------------------------------------------------------
local daemonTask

local function startDaemon()
  daemonTask = hs.task.new(nodeBin, function(code, _, stderr)
    hs.printf("ohmyvoice daemon exited: code=%d stderr=%s", code, stderr)
    hs.timer.doAfter(2, startDaemon)
  end, {daemonScript})

  daemonTask:setEnvironment({
    PATH           = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
    LANG           = "en_US.UTF-8",
    HOME           = os.getenv("HOME"),
    VOICE_ENDPOINT = "http://127.0.0.1:8000/v1/chat/completions",
    -- VOICE_MODEL       = "Qwen/Qwen3-ASR-1.7B",
    -- VOICE_RECORD_ARGS = "-f avfoundation -i :1 -ac 1 -flush_packets 1 -y",
    -- VOICE_START_SOUND_ARGS = "-v 0.6 /System/Library/Sounds/Funk.aiff",
    -- VOICE_STOP_SOUND_ARGS  = "-v 0.6 /System/Library/Sounds/Glass.aiff",
  })

  daemonTask:start()
  hs.printf("ohmyvoice daemon started, pid=%s", tostring(daemonTask:pid()))
end

startDaemon()

----------------------------------------------------------------
-- Hotkey: hold Right Command → record, release → stop
----------------------------------------------------------------
local rightCmdDown = false

voiceTap = hs.eventtap.new(
  {hs.eventtap.event.types.flagsChanged},
  function(event)
    if event:getKeyCode() ~= 54 then return false end
    local flags = event:getFlags()

    if flags.cmd and not rightCmdDown then
      rightCmdDown = true
      hs.task.new(nodeBin, nil, {cliScript, "start"}):start()
      return true
    elseif not flags.cmd and rightCmdDown then
      rightCmdDown = false
      hs.task.new(nodeBin, nil, {cliScript, "stop"}):start()
      return true
    end
    return false
  end
)
voiceTap:start()

-- Watchdog: macOS may silently disable event taps (e.g. after sleep,
-- Secure Input, or security audit).  Re-enable automatically.
hs.timer.doEvery(5, function()
  if not voiceTap:isEnabled() then
    hs.printf("ohmyvoice: event tap was disabled, re-enabling")
    voiceTap:stop()
    voiceTap:start()
  end
end)
