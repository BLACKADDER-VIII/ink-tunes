@rem
@rem Copyright 2015 the original author or authors.
@rem
@rem Licensed under the Apache License, Version 2.0 (the "License");
@rem you may not use this file except in compliance with the License.
@rem You may obtain a copy of the License at
@rem
@rem      https://www.apache.org/licenses/LICENSE-2.0
@rem
@rem Unless required by applicable law or agreed to in writing, software
@rem distributed under the License is distributed on an "AS IS" BASIS,
@rem WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
@rem See the License for the specific language governing permissions and
@rem limitations under the License.
@rem
@rem SPDX-License-Identifier: Apache-2.0
@rem

@if "%DEBUG%"=="" @echo off
@rem ##########################################################################
@rem
@rem  api startup script for Windows
@rem
@rem ##########################################################################

@rem Set local scope for the variables with windows NT shell
if "%OS%"=="Windows_NT" setlocal

set DIRNAME=%~dp0
if "%DIRNAME%"=="" set DIRNAME=.
@rem This is normally unused
set APP_BASE_NAME=%~n0
set APP_HOME=%DIRNAME%..

@rem Resolve any "." and ".." in APP_HOME to make it shorter.
for %%i in ("%APP_HOME%") do set APP_HOME=%%~fi

@rem Add default JVM options here. You can also use JAVA_OPTS and API_OPTS to pass JVM options to this script.
set DEFAULT_JVM_OPTS="--add-exports=java.desktop/sun.awt.image=ALL-UNNAMED" "--enable-native-access=ALL-UNNAMED" "-Djava.awt.headless=true"

@rem Find java.exe
if defined JAVA_HOME goto findJavaFromJavaHome

set JAVA_EXE=java.exe
%JAVA_EXE% -version >NUL 2>&1
if %ERRORLEVEL% equ 0 goto execute

echo. 1>&2
echo ERROR: JAVA_HOME is not set and no 'java' command could be found in your PATH. 1>&2
echo. 1>&2
echo Please set the JAVA_HOME variable in your environment to match the 1>&2
echo location of your Java installation. 1>&2

goto fail

:findJavaFromJavaHome
set JAVA_HOME=%JAVA_HOME:"=%
set JAVA_EXE=%JAVA_HOME%/bin/java.exe

if exist "%JAVA_EXE%" goto execute

echo. 1>&2
echo ERROR: JAVA_HOME is set to an invalid directory: %JAVA_HOME% 1>&2
echo. 1>&2
echo Please set the JAVA_HOME variable in your environment to match the 1>&2
echo location of your Java installation. 1>&2

goto fail

:execute
@rem Setup the command line

set CLASSPATH=%APP_HOME%\lib\api.jar;%APP_HOME%\lib\audiveris.jar;%APP_HOME%\lib\javalin-6.4.0.jar;%APP_HOME%\lib\github-api-1.330.jar;%APP_HOME%\lib\jackson-core-2.20.0.jar;%APP_HOME%\lib\jackson-databind-2.20.0.jar;%APP_HOME%\lib\args4j-2.33.jar;%APP_HOME%\lib\logback-classic-1.4.14.jar;%APP_HOME%\lib\jai-imageio-jpeg2000-1.4.0.jar;%APP_HOME%\lib\jai-imageio-core-1.4.0.jar;%APP_HOME%\lib\itextpdf-5.5.13.2.jar;%APP_HOME%\lib\jgoodies-forms-1.9.0.jar;%APP_HOME%\lib\jgoodies-looks-2.7.0.jar;%APP_HOME%\lib\jaxb-core-2.3.0.1.jar;%APP_HOME%\lib\jaxb-impl-2.3.1.jar;%APP_HOME%\lib\jama-1.0.3.jar;%APP_HOME%\lib\jai-core-1.1.3.jar;%APP_HOME%\lib\jaxb-api-2.3.1.jar;%APP_HOME%\lib\ij-1.54p.jar;%APP_HOME%\lib\jcip-annotations-1.0.jar;%APP_HOME%\lib\org.apache.commons.io-2.4.jar;%APP_HOME%\lib\jbig2-imageio-3.0.4.jar;%APP_HOME%\lib\pdfbox-3.0.6.jar;%APP_HOME%\lib\fontbox-3.0.6.jar;%APP_HOME%\lib\pdfbox-io-3.0.6.jar;%APP_HOME%\lib\proxymusic-4.0.3.jar;%APP_HOME%\lib\eventbus-1.4.jar;%APP_HOME%\lib\tesseract-5.5.1-1.5.12.jar;%APP_HOME%\lib\tesseract-5.5.1-1.5.12-macosx-arm64.jar;%APP_HOME%\lib\leptonica-1.85.0-1.5.12.jar;%APP_HOME%\lib\leptonica-1.85.0-1.5.12-macosx-arm64.jar;%APP_HOME%\lib\javacpp-1.5.12.jar;%APP_HOME%\lib\commonmark-0.27.0.jar;%APP_HOME%\lib\bsaf-1.9.2.jar;%APP_HOME%\lib\jfreechart-1.5.6.jar;%APP_HOME%\lib\jgrapht-core-1.5.2.jar;%APP_HOME%\lib\reflections-0.10.2.jar;%APP_HOME%\lib\websocket-jetty-server-11.0.24.jar;%APP_HOME%\lib\jetty-webapp-11.0.24.jar;%APP_HOME%\lib\websocket-servlet-11.0.24.jar;%APP_HOME%\lib\jetty-servlet-11.0.24.jar;%APP_HOME%\lib\jetty-security-11.0.24.jar;%APP_HOME%\lib\websocket-core-server-11.0.24.jar;%APP_HOME%\lib\jetty-server-11.0.24.jar;%APP_HOME%\lib\websocket-jetty-common-11.0.24.jar;%APP_HOME%\lib\websocket-core-common-11.0.24.jar;%APP_HOME%\lib\jetty-http-11.0.24.jar;%APP_HOME%\lib\jetty-io-11.0.24.jar;%APP_HOME%\lib\jetty-xml-11.0.24.jar;%APP_HOME%\lib\jetty-util-11.0.24.jar;%APP_HOME%\lib\slf4j-api-2.0.17.jar;%APP_HOME%\lib\jna-5.14.0.jar;%APP_HOME%\lib\kotlin-stdlib-jdk7-1.9.25.jar;%APP_HOME%\lib\kotlin-stdlib-1.9.25.jar;%APP_HOME%\lib\kotlin-stdlib-jdk8-1.9.25.jar;%APP_HOME%\lib\jackson-annotations-2.20.jar;%APP_HOME%\lib\logback-core-1.4.14.jar;%APP_HOME%\lib\jgoodies-common-1.8.1.jar;%APP_HOME%\lib\javax.activation-api-1.2.0.jar;%APP_HOME%\lib\commons-io-2.16.1.jar;%APP_HOME%\lib\commons-logging-1.3.5.jar;%APP_HOME%\lib\jaxb-runtime-4.0.5.jar;%APP_HOME%\lib\jaxb-core-4.0.5.jar;%APP_HOME%\lib\jakarta.xml.bind-api-4.0.2.jar;%APP_HOME%\lib\jheaps-0.14.jar;%APP_HOME%\lib\apfloat-1.10.1.jar;%APP_HOME%\lib\commons-lang3-3.18.0.jar;%APP_HOME%\lib\javassist-3.28.0-GA.jar;%APP_HOME%\lib\jsr305-3.0.2.jar;%APP_HOME%\lib\jetty-jakarta-servlet-api-5.0.2.jar;%APP_HOME%\lib\websocket-jetty-api-11.0.24.jar;%APP_HOME%\lib\angus-activation-2.0.2.jar;%APP_HOME%\lib\jakarta.activation-api-2.1.3.jar;%APP_HOME%\lib\annotations-13.0.jar;%APP_HOME%\lib\txw2-4.0.5.jar;%APP_HOME%\lib\istack-commons-runtime-4.1.2.jar


@rem Execute api
"%JAVA_EXE%" %DEFAULT_JVM_OPTS% %JAVA_OPTS% %API_OPTS%  -classpath "%CLASSPATH%" org.audiveris.api.AudiverisApiServer %*

:end
@rem End local scope for the variables with windows NT shell
if %ERRORLEVEL% equ 0 goto mainEnd

:fail
rem Set variable API_EXIT_CONSOLE if you need the _script_ return code instead of
rem the _cmd.exe /c_ return code!
set EXIT_CODE=%ERRORLEVEL%
if %EXIT_CODE% equ 0 set EXIT_CODE=1
if not ""=="%API_EXIT_CONSOLE%" exit %EXIT_CODE%
exit /b %EXIT_CODE%

:mainEnd
if "%OS%"=="Windows_NT" endlocal

:omega
