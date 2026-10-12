# Windows host adapter for physical directory identity and local registration paths.
function Initialize-HomeEdgeFileInformation {
  if (-not ("HomeEdgeDirectoryIdentity" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class HomeEdgeDirectoryIdentity {
  [StructLayout(LayoutKind.Sequential)]
  struct Info {
    public uint Attributes, CreatedLow, CreatedHigh, AccessLow, AccessHigh, WriteLow, WriteHigh;
    public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
  }
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern SafeFileHandle CreateFileW(string path, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern bool GetFileInformationByHandle(SafeFileHandle handle, out Info info);
  public static string Read(string path) {
    using (var handle = CreateFileW(path, 0, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero)) {
      if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
      Info info;
      if (!GetFileInformationByHandle(handle, out info)) throw new Win32Exception(Marshal.GetLastWin32Error());
      if (info.IndexHigh == 0 && info.IndexLow == 0) throw new InvalidOperationException("Directory identity is unavailable; use the directory-local entry.");
      return String.Format("windows-v1:{0:x8}:{1:x8}{2:x8}:{3:x8}{4:x8}", info.Volume, info.IndexHigh, info.IndexLow, info.CreatedHigh, info.CreatedLow);
    }
  }
  public static uint LinkCount(string path) {
    using (var handle = CreateFileW(path, 0, 7, IntPtr.Zero, 3, 0x00200000, IntPtr.Zero)) {
      if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
      Info info;
      if (!GetFileInformationByHandle(handle, out info)) throw new Win32Exception(Marshal.GetLastWin32Error());
      if (info.Links == 0) throw new InvalidOperationException("File link count is unavailable; use the directory-local entry.");
      return info.Links;
    }
  }
}
'@
  }
}

function Get-HomeEdgeDirectoryIdentity([string]$Directory) {
  Initialize-HomeEdgeFileInformation
  return [HomeEdgeDirectoryIdentity]::Read($Directory)
}

function Assert-HomeEdgeRegistrationLeaf([string]$Path) {
  $Item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if ($null -eq $Item) { return }
  if ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Registration path is a link/reparse point; it was not overwritten: $Path" }
  if ($Item.PSIsContainer) { throw "Registration path has an unexpected type; it was not changed: $Path" }
  Initialize-HomeEdgeFileInformation
  if ([HomeEdgeDirectoryIdentity]::LinkCount($Path) -ne 1) { throw "Registration file has multiple hard links; it was not overwritten: $Path" }
}

function Assert-HomeEdgeRegistrationPaths([string]$Directory) {
  foreach ($Relative in @("", "lib", ".home-edge-launcher-owned", "target.txt", "home-edge.cmd", "launch-tui.ps1", "lib\project-location.ps1", "lib\host-launcher.ps1", "lib\ui-language.ps1")) {
    $Path = if ($Relative) { Join-Path $Directory $Relative } else { $Directory }
    $Item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -ne $Item) {
      if ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Registration path is a link/reparse point; it was not overwritten: $Path" }
      $ShouldBeDirectory = $Relative -in @("", "lib")
      if ($Item.PSIsContainer -ne $ShouldBeDirectory) { throw "Registration path has an unexpected type; it was not changed: $Path" }
      if (-not $ShouldBeDirectory) { Assert-HomeEdgeRegistrationLeaf $Path }
    }
  }
}

function Enter-HomeEdgeLauncherLock([string]$Directory) {
  $Path = Join-Path $Directory ".home-edge-launcher.lock"
  try {
    Assert-HomeEdgeRegistrationLeaf $Path
    $Existed = Test-Path -LiteralPath $Path
    $Lock = [IO.File]::Open($Path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  } catch {
    throw "Launcher registration is busy or its lock is unavailable; retry after the other launcher/setup closes. $($_.Exception.Message)"
  }
  try {
    $Header = "home-edge-bootstrap/launcher-lock/v1`n"
    if ($Existed) {
      $Reader = [IO.StreamReader]::new($Lock, [Text.Encoding]::ASCII, $false, 1024, $true)
      try { $Existing = $Reader.ReadToEnd() } finally { $Reader.Dispose() }
      if ($Existing -cne $Header) { throw "Launcher lock has unknown contents; choose an empty launcher directory or inspect it before retrying." }
    } else {
      $Bytes = [Text.Encoding]::ASCII.GetBytes($Header)
      $Lock.Write($Bytes, 0, $Bytes.Length)
      $Lock.Flush()
    }
    return $Lock
  } catch {
    $Lock.Dispose()
    throw
  }
}

function Exit-HomeEdgeLauncherLock([IO.FileStream]$Lock) {
  if ($null -ne $Lock) { $Lock.Dispose() }
}

function Publish-HomeEdgeRegistrationFile([string]$Temporary, [string]$Path) {
  Assert-HomeEdgeRegistrationLeaf $Path
  if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($Temporary, $Path, [NullString]::Value) }
  else { [IO.File]::Move($Temporary, $Path) }
}

function Write-HomeEdgeRegistrationText([string]$Path, [string]$Text, [Text.Encoding]$Encoding) {
  $Temporary = $Path + ".tmp-" + [Guid]::NewGuid().ToString("N")
  try {
    [IO.File]::WriteAllText($Temporary, $Text, $Encoding)
    Publish-HomeEdgeRegistrationFile $Temporary $Path
  } finally {
    if (Test-Path -LiteralPath $Temporary) { Remove-Item -LiteralPath $Temporary -Force }
  }
}

function Copy-HomeEdgeRegistrationFile([string]$Source, [string]$Path) {
  $Temporary = $Path + ".tmp-" + [Guid]::NewGuid().ToString("N")
  try {
    [IO.File]::Copy($Source, $Temporary)
    Publish-HomeEdgeRegistrationFile $Temporary $Path
  } finally {
    if (Test-Path -LiteralPath $Temporary) { Remove-Item -LiteralPath $Temporary -Force }
  }
}
