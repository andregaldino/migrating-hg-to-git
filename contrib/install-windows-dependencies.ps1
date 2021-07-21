# install-dependencies.ps1 - Install Windows dependencies for building Mercurial
#
# Copyright 2019 Gregory Szorc <gregory.szorc@gmail.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

# This script can be used to bootstrap a Mercurial build environment on
# Windows.
#
# The script makes a lot of assumptions about how things should work.
# For example, the install location of Python is hardcoded to c:\hgdev\*.
#
# The script should be executed from a PowerShell with elevated privileges
# if you don't want to see a UAC prompt for various installers.
#
# The script is tested on Windows 10 and Windows Server 2019 (in EC2).

$VS_BUILD_TOOLS_URL = "https://download.visualstudio.microsoft.com/download/pr/a1603c02-8a66-4b83-b821-811e3610a7c4/aa2db8bb39e0cbd23e9940d8951e0bc3/vs_buildtools.exe"
$VS_BUILD_TOOLS_SHA256 = "911E292B8E6E5F46CBC17003BDCD2D27A70E616E8D5E6E69D5D489A605CAA139"

$VC9_PYTHON_URL = "https://download.microsoft.com/download/7/9/6/796EF2E4-801B-4FC4-AB28-B59FBF6D907B/VCForPython27.msi"
$VC9_PYTHON_SHA256 = "070474db76a2e625513a5835df4595df9324d820f9cc97eab2a596dcbc2f5cbf"

$PYTHON27_x64_URL = "https://www.python.org/ftp/python/2.7.18/python-2.7.18.amd64.msi"
$PYTHON27_x64_SHA256 = "b74a3afa1e0bf2a6fc566a7b70d15c9bfabba3756fb077797d16fffa27800c05"
$PYTHON27_X86_URL = "https://www.python.org/ftp/python/2.7.18/python-2.7.18.msi"
$PYTHON27_X86_SHA256 = "d901802e90026e9bad76b8a81f8dd7e43c7d7e8269d9281c9e9df7a9c40480a9"

$PYTHON37_x86_URL = "https://www.python.org/ftp/python/3.7.9/python-3.7.9.exe"
$PYTHON37_x86_SHA256 = "769bb7c74ad1df6d7d74071cc16a984ff6182e4016e11b8949b93db487977220"
$PYTHON37_X64_URL = "https://www.python.org/ftp/python/3.7.9/python-3.7.9-amd64.exe"
$PYTHON37_x64_SHA256 = "e69ed52afb5a722e5c56f6c21d594e85c17cb29f12f18bb69751cf1714e0f987"

$PYTHON38_x86_URL = "https://www.python.org/ftp/python/3.8.10/python-3.8.10.exe"
$PYTHON38_x86_SHA256 = "ad07633a1f0cd795f3bf9da33729f662281df196b4567fa795829f3bb38a30ac"
$PYTHON38_x64_URL = "https://www.python.org/ftp/python/3.8.10/python-3.8.10-amd64.exe"
$PYTHON38_x64_SHA256 = "7628244cb53408b50639d2c1287c659f4e29d3dfdb9084b11aed5870c0c6a48a"

$PYTHON39_x86_URL = "https://www.python.org/ftp/python/3.9.5/python-3.9.5.exe"
$PYTHON39_x86_SHA256 = "505129081a839b699a6ab9064b441ad922ef03767b5dd4241fd0c2166baf64de"
$PYTHON39_x64_URL = "https://www.python.org/ftp/python/3.9.5/python-3.9.5-amd64.exe"
$PYTHON39_x64_SHA256 = "84d5243088ba00c11e51905c704dbe041040dfff044f4e1ce5476844ee2e6eac"

# PIP 19.2.3.
$PIP_URL = "https://github.com/pypa/get-pip/raw/309a56c5fd94bd1134053a541cb4657a4e47e09d/get-pip.py"
$PIP_SHA256 = "57e3643ff19f018f8a00dfaa6b7e4620e3c1a7a2171fd218425366ec006b3bfe"

$VIRTUALENV_URL = "https://files.pythonhosted.org/packages/66/f0/6867af06d2e2f511e4e1d7094ff663acdebc4f15d4a0cb0fed1007395124/virtualenv-16.7.5.tar.gz"
$VIRTUALENV_SHA256 = "f78d81b62d3147396ac33fc9d77579ddc42cc2a98dd9ea38886f616b33bc7fb2"

$INNO_SETUP_URL = "http://files.jrsoftware.org/is/5/innosetup-5.6.1-unicode.exe"
$INNO_SETUP_SHA256 = "27D49E9BC769E9D1B214C153011978DB90DC01C2ACD1DDCD9ED7B3FE3B96B538"

$MINGW_BIN_URL = "https://osdn.net/frs/redir.php?m=constant&f=mingw%2F68260%2Fmingw-get-0.6.3-mingw32-pre-20170905-1-bin.zip"
$MINGW_BIN_SHA256 = "2AB8EFD7C7D1FC8EAF8B2FA4DA4EEF8F3E47768284C021599BC7435839A046DF"

$MERCURIAL_WHEEL_FILENAME = "mercurial-5.1.2-cp27-cp27m-win_amd64.whl"
$MERCURIAL_WHEEL_URL = "https://files.pythonhosted.org/packages/6d/47/e031e47f7fe9b16e4e3383da47e2b0a7eae6e603996bc67a03ec4fa1b3f4/$MERCURIAL_WHEEL_FILENAME"
$MERCURIAL_WHEEL_SHA256 = "1d18c7f6ca1456f0f62ee65c9a50c14cbba48ce6e924930cdb10537f5c9eaf5f"

$RUSTUP_INIT_URL = "https://static.rust-lang.org/rustup/archive/1.21.1/x86_64-pc-windows-gnu/rustup-init.exe"
$RUSTUP_INIT_SHA256 = "d17df34ba974b9b19cf5c75883a95475aa22ddc364591d75d174090d55711c72"

$PYOXIDIZER_URL = "https://github.com/indygreg/PyOxidizer/releases/download/pyoxidizer%2F0.16.0/PyOxidizer-0.16.0-x64.msi"
$PYOXIDIZER_SHA256 = "2a9c58add9161c272c418d5e6dec13fbe648f624b5d26770190357e4d664f24e"

# Writing progress slows down downloads substantially. So disable it.
$progressPreference = 'silentlyContinue'

function Secure-Download($url, $path, $sha256) {
    if (Test-Path -Path $path) {
        Get-FileHash -Path $path -Algorithm SHA256 -OutVariable hash

        if ($hash.Hash -eq $sha256) {
            Write-Output "SHA256 of $path verified as $sha256"
            return
        }

        Write-Output "hash mismatch on $path; downloading again"
    }

    Write-Output "downloading $url to $path"
    Invoke-WebRequest -Uri $url -OutFile $path
    Get-FileHash -Path $path -Algorithm SHA256 -OutVariable hash

    if ($hash.Hash -ne $sha256) {
        Remove-Item -Path $path
        throw "hash mismatch when downloading $url; got $($hash.Hash), expected $sha256"
    }
}

function Invoke-Process($path, $arguments) {
    $p = Start-Process -FilePath $path -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden

    if ($p.ExitCode -ne 0) {
        throw "process exited non-0: $($p.ExitCode)"
    }
}

function Install-Python3($name, $installer, $dest, $pip) {
    Write-Output "installing $name"

    # We hit this when running the script as part of Simple Systems Manager in
    # EC2. The Python 3 installer doesn't seem to like per-user installs
    # when running as the SYSTEM user. So enable global installs if executed in
    # this mode.
    if ($env:USERPROFILE -eq "C:\Windows\system32\config\systemprofile") {
        Write-Output "running with SYSTEM account; installing for all users"
        $allusers = "1"
    }
    else {
        $allusers = "0"
    }

    Invoke-Process $installer "/quiet TargetDir=${dest} InstallAllUsers=${allusers} AssociateFiles=0 CompileAll=0 PrependPath=0 Include_doc=0 Include_launcher=0 InstallLauncherAllUsers=0 Include_pip=0 Include_test=0"
    Invoke-Process ${dest}\python.exe $pip
}

function Install-Rust($prefix) {
    Write-Output "installing Rust"
    $Env:RUSTUP_HOME = "${prefix}\rustup"
    $Env:CARGO_HOME = "${prefix}\cargo"

    Invoke-Process "${prefix}\assets\rustup-init.exe" "-y --default-host x86_64-pc-windows-msvc"
    Invoke-Process "${prefix}\cargo\bin\rustup.exe" "target add i686-pc-windows-msvc"
    Invoke-Process "${prefix}\cargo\bin\rustup.exe" "install 1.52.0"
    Invoke-Process "${prefix}\cargo\bin\rustup.exe" "component add clippy"
}

function Install-Dependencies($prefix) {
    if (!(Test-Path -Path $prefix\assets)) {
        New-Item -Path $prefix\assets -ItemType Directory
    }

    $pip = "${prefix}\assets\get-pip.py"

    Secure-Download $VC9_PYTHON_URL ${prefix}\assets\VCForPython27.msi $VC9_PYTHON_SHA256
    Secure-Download $PYTHON27_x86_URL ${prefix}\assets\python27-x86.msi $PYTHON27_x86_SHA256
    Secure-Download $PYTHON27_x64_URL ${prefix}\assets\python27-x64.msi $PYTHON27_x64_SHA256
    Secure-Download $PYTHON37_x86_URL ${prefix}\assets\python37-x86.exe $PYTHON37_x86_SHA256
    Secure-Download $PYTHON37_x64_URL ${prefix}\assets\python37-x64.exe $PYTHON37_x64_SHA256
    Secure-Download $PYTHON38_x86_URL ${prefix}\assets\python38-x86.exe $PYTHON38_x86_SHA256
    Secure-Download $PYTHON38_x64_URL ${prefix}\assets\python38-x64.exe $PYTHON38_x64_SHA256
    Secure-Download $PYTHON39_x86_URL ${prefix}\assets\python39-x86.exe $PYTHON39_x86_SHA256
    Secure-Download $PYTHON39_x64_URL ${prefix}\assets\python39-x64.exe $PYTHON39_x64_SHA256
    Secure-Download $PIP_URL ${pip} $PIP_SHA256
    Secure-Download $VIRTUALENV_URL ${prefix}\assets\virtualenv.tar.gz $VIRTUALENV_SHA256
    Secure-Download $VS_BUILD_TOOLS_URL ${prefix}\assets\vs_buildtools.exe $VS_BUILD_TOOLS_SHA256
    Secure-Download $INNO_SETUP_URL ${prefix}\assets\InnoSetup.exe $INNO_SETUP_SHA256
    Secure-Download $MINGW_BIN_URL ${prefix}\assets\mingw-get-bin.zip $MINGW_BIN_SHA256
    Secure-Download $MERCURIAL_WHEEL_URL ${prefix}\assets\${MERCURIAL_WHEEL_FILENAME} $MERCURIAL_WHEEL_SHA256
    Secure-Download $RUSTUP_INIT_URL ${prefix}\assets\rustup-init.exe $RUSTUP_INIT_SHA256
    Secure-Download $PYOXIDIZER_URL ${prefix}\assets\PyOxidizer.msi $PYOXIDIZER_SHA256

    Write-Output "installing Python 2.7 32-bit"
    Invoke-Process msiexec.exe "/i ${prefix}\assets\python27-x86.msi /l* ${prefix}\assets\python27-x86.log /q TARGETDIR=${prefix}\python27-x86 ALLUSERS="
    Invoke-Process ${prefix}\python27-x86\python.exe ${prefix}\assets\get-pip.py
    Invoke-Process ${prefix}\python27-x86\Scripts\pip.exe "install ${prefix}\assets\virtualenv.tar.gz"

    Write-Output "installing Python 2.7 64-bit"
    Invoke-Process msiexec.exe "/i ${prefix}\assets\python27-x64.msi /l* ${prefix}\assets\python27-x64.log /q TARGETDIR=${prefix}\python27-x64 ALLUSERS="
    Invoke-Process ${prefix}\python27-x64\python.exe ${prefix}\assets\get-pip.py
    Invoke-Process ${prefix}\python27-x64\Scripts\pip.exe "install ${prefix}\assets\virtualenv.tar.gz"

    Install-Python3 "Python 3.7 32-bit" ${prefix}\assets\python37-x86.exe ${prefix}\python37-x86 ${pip}
    Install-Python3 "Python 3.7 64-bit" ${prefix}\assets\python37-x64.exe ${prefix}\python37-x64 ${pip}
    Install-Python3 "Python 3.8 32-bit" ${prefix}\assets\python38-x86.exe ${prefix}\python38-x86 ${pip}
    Install-Python3 "Python 3.8 64-bit" ${prefix}\assets\python38-x64.exe ${prefix}\python38-x64 ${pip}
    Install-Python3 "Python 3.9 32-bit" ${prefix}\assets\python39-x86.exe ${prefix}\python39-x86 ${pip}
    Install-Python3 "Python 3.9 64-bit" ${prefix}\assets\python39-x64.exe ${prefix}\python39-x64 ${pip}

    Write-Output "installing Visual Studio 2017 Build Tools and SDKs"
    Invoke-Process ${prefix}\assets\vs_buildtools.exe "--quiet --wait --norestart --nocache --channelUri https://aka.ms/vs/15/release/channel --add Microsoft.VisualStudio.Workload.MSBuildTools --add Microsoft.VisualStudio.Component.Windows10SDK.17763 --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.Windows10SDK --add Microsoft.VisualStudio.Component.VC.140"

    Write-Output "installing PyOxidizer"
    Invoke-Process msiexec.exe "/i ${prefix}\assets\PyOxidizer.msi /l* ${prefix}\assets\PyOxidizer.log /quiet"

    Install-Rust ${prefix}

    Write-Output "installing Visual C++ 9.0 for Python 2.7"
    Invoke-Process msiexec.exe "/i ${prefix}\assets\VCForPython27.msi /l* ${prefix}\assets\VCForPython27.log /q"

    Write-Output "installing Inno Setup"
    Invoke-Process ${prefix}\assets\InnoSetup.exe "/SP- /VERYSILENT /SUPPRESSMSGBOXES"

    Write-Output "extracting MinGW base archive"
    Expand-Archive -Path ${prefix}\assets\mingw-get-bin.zip -DestinationPath "${prefix}\MinGW" -Force

    Write-Output "updating MinGW package catalogs"
    Invoke-Process ${prefix}\MinGW\bin\mingw-get.exe "update"

    Write-Output "installing MinGW packages"
    Invoke-Process ${prefix}\MinGW\bin\mingw-get.exe "install msys-base msys-coreutils msys-diffutils msys-unzip"

    # Construct a virtualenv useful for bootstrapping. It conveniently contains a
    # Mercurial install.
    Write-Output "creating bootstrap virtualenv with Mercurial"
    Invoke-Process "$prefix\python27-x64\Scripts\virtualenv.exe" "${prefix}\venv-bootstrap"
    Invoke-Process "${prefix}\venv-bootstrap\Scripts\pip.exe" "install ${prefix}\assets\${MERCURIAL_WHEEL_FILENAME}"
}

function Clone-Mercurial-Repo($prefix, $repo_url, $dest) {
    Write-Output "cloning $repo_url to $dest"
    # TODO Figure out why CA verification isn't working in EC2 and remove
    # --insecure.
    Invoke-Process "${prefix}\venv-bootstrap\Scripts\hg.exe" "clone --insecure $repo_url $dest"

    # Mark repo as non-publishing by default for convenience.
    Add-Content -Path "$dest\.hg\hgrc" -Value "`n[phases]`npublish = false"
}

$prefix = "c:\hgdev"
Install-Dependencies $prefix
Clone-Mercurial-Repo $prefix "https://www.mercurial-scm.org/repo/hg" $prefix\src
