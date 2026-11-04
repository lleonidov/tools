@echo off
setlocal

set "HTTP_PROXY=socks5h://Fangorn:12999"
set "HTTPS_PROXY=socks5h://Fangorn:12999"
set "ALL_PROXY=socks5h://Fangorn:12999"
set "NO_PROXY=localhost,127.0.0.1,::1"

call code --new-window "%~dp0."
endlocal