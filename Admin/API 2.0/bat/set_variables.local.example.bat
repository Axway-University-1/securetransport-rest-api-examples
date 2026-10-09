@echo off
REM ==============================================================================
REM Copy this file to set_variables.local.bat and fill in your own values.
REM
REM   copy set_variables.local.example.bat set_variables.local.bat
REM
REM set_variables.local.bat is excluded from git, so your credentials are never
REM committed. The values here override the placeholders in set_variables.bat.
REM ==============================================================================

REM The SecureTransport host, without the protocol or port
set ST_SERVER=st.example.com

REM The admin port. 8444 for a non root install, 444 for a root install.
set ST_PORT=8444

REM An administrator account and its password, in plain text
set ST_USER=apiadmin
set ST_PASSWORD=change_me

REM Optional. Some examples need an account that already exists and, for the SSH
REM sites, the partner's SSH port. They use john and 8022; remove the REM to use
REM your own. An argument given to an example still wins over these.
REM set ST_EXAMPLE_ACCOUNT=john
REM set ST_SSH_PORT=8022
