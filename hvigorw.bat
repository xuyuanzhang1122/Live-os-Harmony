@echo off
setlocal

set "HVIGOR_BIN="
if defined DEVECO_HOME if exist "%DEVECO_HOME%\tools\hvigor\bin\hvigorw.bat" set "HVIGOR_BIN=%DEVECO_HOME%\tools\hvigor\bin\hvigorw.bat"
if not defined HVIGOR_BIN if defined DEVECO_SDK_HOME if exist "%DEVECO_SDK_HOME%\..\tools\hvigor\bin\hvigorw.bat" set "HVIGOR_BIN=%DEVECO_SDK_HOME%\..\tools\hvigor\bin\hvigorw.bat"
if not defined HVIGOR_BIN if exist "D:\DevEco Studio\tools\hvigor\bin\hvigorw.bat" set "HVIGOR_BIN=D:\DevEco Studio\tools\hvigor\bin\hvigorw.bat"
if not defined HVIGOR_BIN if exist "%ProgramFiles%\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" set "HVIGOR_BIN=%ProgramFiles%\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat"

if not defined HVIGOR_BIN (
  echo ERROR: DevEco Studio Hvigor was not found. Set DEVECO_HOME or DEVECO_SDK_HOME.
  exit /b 1
)

if not defined HVIGOR_USER_HOME set "HVIGOR_USER_HOME=%USERPROFILE%\.hvigor"
for %%i in ("%HVIGOR_BIN%") do set "HVIGOR_DIR=%%~dpi"
if not defined NODE_HOME for %%i in ("%HVIGOR_DIR%\..\..\node") do set "NODE_HOME=%%~fi"
if not defined DEVECO_SDK_HOME for %%i in ("%HVIGOR_DIR%\..\..\..\sdk") do set "DEVECO_SDK_HOME=%%~fi"
if not defined JAVA_HOME for %%i in ("%HVIGOR_DIR%\..\..\..\jbr") do set "JAVA_HOME=%%~fi"
set "PATH=%NODE_HOME%;%JAVA_HOME%\bin;%PATH%"

call "%HVIGOR_BIN%" %*
exit /b %ERRORLEVEL%
