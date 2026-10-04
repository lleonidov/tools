@for /f "tokens=2 delims=:." %%a in ('chcp') do @set "_opm_cp=%%a"
@chcp 65001 > nul
@call oscript "F:\project\tools\tools\vrunner-2.6\oscript_modules\vanessa-runner\src\main.os" %*
@set _opm_err=%ERRORLEVEL%
@chcp %_opm_cp% > nul
@exit /b %_opm_err%
