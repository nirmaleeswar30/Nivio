@echo off
REM CMake wrapper to replace VS 16 2019 with VS 17 2022

set "ARGS=%*"
set "ARGS=%ARGS:Visual Studio 16 2019=Visual Studio 17 2022%"

"C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" %ARGS%
