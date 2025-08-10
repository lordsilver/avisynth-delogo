@echo off
setlocal
set "toolchain_root=%~dp0"
set "plugin_root=%toolchain_root%Plugins"
set "avspmod_root=%toolchain_root%AvsPmod"

if not exist "%toolchain_root%AviSynth.dll" (
  echo AviSynth.dll is missing from the toolchain root.
  exit /b 1
)

if not exist "%avspmod_root%\AvsPmod.exe" (
  echo AvsPmod.exe is missing from the toolchain.
  exit /b 1
)

reg.exe add "HKCU\Software\AviSynth" /v "PluginDir+" /t REG_SZ /d "%plugin_root%" /f >nul
if errorlevel 1 (
  echo Failed to configure the current-user AviSynth plugin directory.
  exit /b 1
)

set "PATH=%toolchain_root%;%PATH%"
pushd "%avspmod_root%" || exit /b 1
start "" "AvsPmod.exe" %*
set "launch_status=%errorlevel%"
popd
exit /b %launch_status%
