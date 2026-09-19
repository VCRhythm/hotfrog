@echo off
rem bugloop for this project (installed by /bugloop init). Run from the project root like `rojo serve`:
rem   bugloop                 daily: listener in the background + the fixer-loop session in this window (rojo serve stays yours)
rem   bugloop down            stop that background listener
rem   bugloop serve           only the listener, in this window (like `rojo serve`)
rem   bugloop launch          only the fixer-loop Claude Code session
rem   bugloop status | pending | add "note" | projects | upgrade ...   any bugloop.py command
setlocal
set "SKILL=%USERPROFILE%\.claude\skills\bugloop\scripts\bugloop.py"
if "%~1"=="" (
  python "%SKILL%" --repo "%~dp0." up
) else (
  python "%SKILL%" --repo "%~dp0." %*
)
