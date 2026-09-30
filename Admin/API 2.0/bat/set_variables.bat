@echo off
REM ==============================================================================
REM Script Name: set_variables.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This batch script sets environment variables required for API authentication
REM and connectivity. It is intended to be called by other scripts that rely on
REM ST_SERVER, ST_PORT, ST_USER, and ST_PASSWORD values.
REM
REM Usage:
REM call set_variables.bat
REM
REM Notes:
REM - Ensure this script is called from another batch file to retain variables.
REM - Values should be securely managed and updated as needed.
REM - Rather than editing this file, put your own values in set_variables.local.bat
REM   next to it. That file is excluded from git, so your credentials are never
REM   committed. Anything it sets overrides the placeholders below.
REM ==============================================================================

set ST_SERVER=
set ST_PORT=
set ST_USER=
set ST_PASSWORD=

REM
REM Load the local overrides, if present. Keep your real server and credentials
REM here so that they stay out of the repository.
REM
IF EXIST "%~dp0set_variables.local.bat" CALL "%~dp0set_variables.local.bat"
