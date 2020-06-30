@echo off
setlocal enabledelayedexpansion
set args=%*
:: replace problem characters in arguments
set args=%args:"='%
set args=%args:(=`(%
set args=%args:)=`)%
set invalid="='
if !args! == !invalid! ( set args= )
set executable=%~dp0%~n0.ps1
powershell -noprofile -ex unrestricted "& '%executable%' %args%;exit $lastexitcode"
