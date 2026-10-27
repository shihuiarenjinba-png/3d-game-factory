param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z][a-z0-9-]{3,39}$')]
    [string]$Slug,
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$OutputDirectory = 'dist'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Stop-Hold([string]$Message) { throw "HOLD: $Message" }

function Read-JsonObject([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Stop-Hold "required JSON file is missing: $Path" }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Stop-Hold "invalid JSON file: $Path" }
}

function Require-Text($Object, [string]$Property, [int]$MaxLength = 512) {
    $value = $Object.$Property
    if ($null -eq $value -or -not ($value -is [string]) -or [string]::IsNullOrWhiteSpace($value) -or $value.Length -gt $MaxLength) {
        Stop-Hold "missing or invalid field: $Property"
    }
    return $value
}

function Xml-Escape([string]$Value) { return [System.Security.SecurityElement]::Escape($Value) }

$root = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$productRoot = Join-Path $root ("products\" + $Slug)
if (-not (Test-Path -LiteralPath $productRoot -PathType Container)) { Stop-Hold "3D product directory is missing: products/$Slug" }

$project = Join-Path $productRoot 'project.godot'
$presets = Join-Path $productRoot 'export_presets.cfg'
foreach ($required in @($project, $presets)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { Stop-Hold "Godot source is incomplete: $required" }
}

$storeRoot = Join-Path $productRoot 'store'
$identityPath = Join-Path $storeRoot 'approved-identity.json'
$metadataPath = Join-Path $storeRoot 'package-metadata.json'
$identity = Read-JsonObject $identityPath
$metadata = Read-JsonObject $metadataPath

if ($identity.reviewed -ne $true -or $identity.source -ne 'partner_center') {
    Stop-Hold 'approved identity is not a reviewed Partner Center record'
}

$requestId = Require-Text $identity 'request_id' 128
$productType = Require-Text $identity 'product_type' 32
$sourceFactory = Require-Text $identity 'source_factory' 100
$sourceRepository = Require-Text $identity 'source_repository' 200
$sourceBranch = Require-Text $identity 'source_branch' 240
$identitySlug = Require-Text $identity 'slug' 40
$storeId = Require-Text $identity 'store_id' 32
$identityName = Require-Text $identity 'name' 50
$publisher = Require-Text $identity 'publisher' 512
$version = Require-Text $identity 'version' 32
$packageFamilyName = Require-Text $identity 'package_family_name' 256
$packageSid = Require-Text $identity 'package_sid' 512
$verifiedSourceSha = Require-Text $identity 'verified_source_sha' 40
$expectedHeadSha = Require-Text $identity 'expected_head_sha' 40
$localPackageSha256 = Require-Text $identity 'local_package_sha256' 64
$localPackageKind = Require-Text $identity 'local_package_kind' 16
$localSignatureStatus = Require-Text $identity 'local_signature_status' 80
$evidenceUrl = Require-Text $identity 'evidence_url' 2048
$verifiedBy = Require-Text $identity 'verified_by' 100

if ($requestId -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{3,127}$') { Stop-Hold 'invalid request_id' }
if ($productType -ne 'GAME_3D') { Stop-Hold 'approved identity product_type mismatch' }
if ($sourceFactory -ne '3d-game-factory') { Stop-Hold 'approved identity source_factory mismatch' }
if ($sourceRepository -ne 'shihuiarenjinba-png/3d-game-factory') { Stop-Hold 'approved identity source_repository mismatch' }
if ($sourceBranch -ne 'codex/3d-real-msix-build-path-20261027') { Stop-Hold 'approved identity source_branch mismatch' }
if ($identitySlug -ne $Slug) { Stop-Hold 'approved identity slug mismatch' }
if ($storeId -notmatch '^[A-Za-z0-9]{8,32}$') { Stop-Hold 'invalid Store ID format' }
if ($identityName -notmatch '^[A-Za-z][A-Za-z0-9._-]{2,49}$') { Stop-Hold 'invalid package Identity Name' }
if ($publisher -notmatch '^CN=') { Stop-Hold 'invalid Publisher subject' }
if ($version -notmatch '^\d{1,5}(\.\d{1,5}){3}$') { Stop-Hold 'invalid four-part package version' }
if ($verifiedSourceSha -notmatch '^[0-9a-f]{40}$') { Stop-Hold 'verified source SHA is missing or malformed' }
if ($expectedHeadSha -ne $verifiedSourceSha) { Stop-Hold 'expected HEAD SHA differs from verified source SHA' }
if ($localPackageSha256 -notmatch '^[0-9a-f]{64}$') { Stop-Hold 'local package SHA-256 is malformed' }
if ($localPackageKind -notin @('exe','msix','appx')) { Stop-Hold 'local package kind is invalid' }
if (-not ($packageSid.StartsWith('S-1-15-2-'))) { Stop-Hold 'official Package SID is malformed' }
try { $evidence = [Uri]$evidenceUrl } catch { Stop-Hold 'invalid Partner Center evidence URL' }
if ($evidence.Scheme -ne 'https' -or $evidence.Host -notin @('partner.microsoft.com', 'partnercenter.microsoft.com')) {
    Stop-Hold 'untrusted Partner Center evidence URL'
}

$displayName = if ($identity.display_name) { [string]$identity.display_name } else { Require-Text $metadata 'display_name' 100 }
$publisherDisplayName = if ($identity.publisher_display_name) { [string]$identity.publisher_display_name } else { Require-Text $metadata 'publisher_display_name' 100 }
$description = Require-Text $metadata 'description' 200
$language = Require-Text $metadata 'language' 20
$minWindows = Require-Text $metadata 'min_windows_version' 32
$maxWindows = Require-Text $metadata 'max_windows_version_tested' 32
foreach ($osVersion in @($minWindows, $maxWindows)) {
    if ($osVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') { Stop-Hold 'Windows version metadata must use four-part notation' }
}

Push-Location $root
try {
    $currentHead = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentHead -notmatch '^[0-9a-f]{40}$') { Stop-Hold 'cannot resolve current Git HEAD' }
    $currentBranch = (& git symbolic-ref --quiet --short HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentBranch -ne 'codex/3d-real-msix-build-path-20261027') {
        Stop-Hold 'MSIX build requires the approved 3D Factory work branch'
    }
    # An unsigned package must never be built from a dirty/untracked product
    # while evidence incorrectly claims the clean commit HEAD as its source.
    $productChanges = @(& git status --porcelain --untracked-files=all -- ("products/" + $Slug))
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'cannot inspect product working tree' }
    if ($productChanges.Count -gt 0) {
        Stop-Hold 'product has uncommitted or untracked files; commit and review before MSIX build'
    }
    & git cat-file -e ($verifiedSourceSha + '^{commit}') 2>$null
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'verified source SHA is not present in checkout history' }
    $changed = @(& git diff --name-only ($verifiedSourceSha + '..HEAD') -- ("products/" + $Slug))
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'cannot compare product source to verified source SHA' }
    $allowedIdentityPath = "products/$Slug/store/approved-identity.json"
    $unexpected = @($changed | Where-Object { $_ -and $_ -ne $allowedIdentityPath })
    if ($unexpected.Count -gt 0) { Stop-Hold ("product changed after Identity verification: " + ($unexpected -join ', ')) }
}
finally { Pop-Location }

foreach ($asset in @('StoreLogo.png','Square150.png','Square44.png')) {
    $path = Join-Path $storeRoot $asset
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
        Stop-Hold "required Store asset is missing or empty: $asset"
    }
}

$godot = $env:GODOT_EXE
if ([string]::IsNullOrWhiteSpace($godot) -or -not (Test-Path -LiteralPath $godot -PathType Leaf)) { Stop-Hold 'GODOT_EXE is not configured' }

$outRoot = Join-Path $root $OutputDirectory
$godotOut = Join-Path $outRoot 'godot'
$layout = Join-Path $outRoot 'msix-layout'
Remove-Item -LiteralPath $godotOut -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $layout -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $godotOut, (Join-Path $layout 'Game'), (Join-Path $layout 'Assets') | Out-Null

$rawExe = Join-Path $godotOut 'game.exe'
& $godot --headless --path $productRoot --export-release 'Windows Desktop' $rawExe
if ($LASTEXITCODE -ne 0) { Stop-Hold 'Godot Windows export failed' }
if (-not (Test-Path -LiteralPath $rawExe -PathType Leaf) -or (Get-Item -LiteralPath $rawExe).Length -lt 1024) {
    Stop-Hold 'Godot export produced no usable executable'
}
$stream = [System.IO.File]::OpenRead($rawExe)
try {
    $b0 = $stream.ReadByte(); $b1 = $stream.ReadByte()
} finally { $stream.Dispose() }
if ($b0 -ne 0x4D -or $b1 -ne 0x5A) { Stop-Hold 'Godot export is not a Windows PE executable' }

Copy-Item -LiteralPath $rawExe -Destination (Join-Path $layout 'Game\game.exe')
$presetText = Get-Content -LiteralPath $presets -Raw -Encoding UTF8
if ($presetText -match '(?m)^\s*binary_format/embed_pck\s*=\s*false\s*$') {
    $rawPck = [System.IO.Path]::ChangeExtension($rawExe, '.pck')
    if (-not (Test-Path -LiteralPath $rawPck -PathType Leaf) -or (Get-Item -LiteralPath $rawPck).Length -eq 0) {
        Stop-Hold 'Godot export omitted required external PCK'
    }
    Copy-Item -LiteralPath $rawPck -Destination (Join-Path $layout 'Game\game.pck')
}

Copy-Item -LiteralPath (Join-Path $storeRoot 'StoreLogo.png') -Destination (Join-Path $layout 'Assets\StoreLogo.png')
Copy-Item -LiteralPath (Join-Path $storeRoot 'Square150.png') -Destination (Join-Path $layout 'Assets\Square150.png')
Copy-Item -LiteralPath (Join-Path $storeRoot 'Square44.png') -Destination (Join-Path $layout 'Assets\Square44.png')

$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:uap10="http://schemas.microsoft.com/appx/manifest/uap/windows10/10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  IgnorableNamespaces="uap uap10 rescap">
  <Identity Name="$(Xml-Escape $identityName)" Version="$(Xml-Escape $version)" Publisher="$(Xml-Escape $publisher)" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>$(Xml-Escape $displayName)</DisplayName>
    <PublisherDisplayName>$(Xml-Escape $publisherDisplayName)</PublisherDisplayName>
    <Description>$(Xml-Escape $description)</Description>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Resources>
    <Resource Language="$(Xml-Escape $language)" />
  </Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="$(Xml-Escape $minWindows)" MaxVersionTested="$(Xml-Escape $maxWindows)" />
  </Dependencies>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
  <Applications>
    <Application Id="Game" Executable="Game\game.exe" uap10:RuntimeBehavior="packagedClassicApp" uap10:TrustLevel="mediumIL">
      <uap:VisualElements DisplayName="$(Xml-Escape $displayName)" Description="$(Xml-Escape $description)" Square150x150Logo="Assets\Square150.png" Square44x44Logo="Assets\Square44.png" BackgroundColor="transparent" />
    </Application>
  </Applications>
</Package>
"@
$manifestPath = Join-Path $layout 'AppxManifest.xml'
[System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))

$makeAppx = Get-Command makeappx.exe -ErrorAction SilentlyContinue
if ($null -eq $makeAppx) {
    $sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $makeAppx = Get-ChildItem -LiteralPath $sdkRoot -Filter makeappx.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\makeappx\.exe$' } |
        Sort-Object FullName -Descending | Select-Object -First 1
}
if ($null -eq $makeAppx) { Stop-Hold 'MakeAppx.exe was not found in the Windows SDK' }

$packageName = "${Slug}_${version}_x64_QA_UNSIGNED.msix"
$packagePath = Join-Path $outRoot $packageName
Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
& $makeAppx.Source pack /o /v /d $layout /p $packagePath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { Stop-Hold 'MakeAppx failed to create MSIX' }

$hash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
$evidenceOut = [ordered]@{
    schema_version = '1.0'
    status = 'QA_UNSIGNED_MSIX'
    slug = $Slug
    request_id = $requestId
    product_type = $productType
    source_factory = $sourceFactory
    source_repository = $sourceRepository
    source_branch = $sourceBranch
    source_sha = $verifiedSourceSha
    factory_build_head = $currentHead
    identity_verified_source_sha = $verifiedSourceSha
    expected_head_sha = $expectedHeadSha
    local_package_sha256 = $localPackageSha256
    local_package_kind = $localPackageKind
    local_signature_status = $localSignatureStatus
    store_id = $storeId
    identity_name = $identityName
    publisher = $publisher
    version = $version
    verified_by = $verifiedBy
    evidence_url = $evidenceUrl
    msix_file = $packageName
    msix_sha256 = $hash
    signature_verified = $false
    windows_gpu_qa = 'NOT_RUN'
    store_submission = 'NOT_RUN'
}
$evidencePath = Join-Path $outRoot 'msix-evidence.json'
$evidenceOut | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $evidencePath -Encoding UTF8

# Publish a separate, strict two-file handoff for Windows-all-auto.
# The QA_UNSIGNED artifact is never a Store submission or certification claim.
$handoffRoot = Join-Path $outRoot 'handoff'
New-Item -ItemType Directory -Force -Path $handoffRoot | Out-Null
$handoffPackage = Join-Path $handoffRoot 'package.msix'
Copy-Item -LiteralPath $packagePath -Destination $handoffPackage -Force
$handoff = [ordered]@{
    schema_version = 1
    request_id = $requestId
    product_type = $productType
    source_factory = $sourceFactory
    source_repository = $sourceRepository
    source_branch = $sourceBranch
    source_sha = $verifiedSourceSha
    factory_build_head = $currentHead
    local_package_sha256 = $localPackageSha256
    type = '3d-game'
    slug = $Slug
    package = 'package.msix'
    status = 'QA_UNSIGNED'
    package_sha256 = $hash
    package_bytes = (Get-Item -LiteralPath $packagePath).Length
    identity = [ordered]@{
        store_id = $storeId
        name = $identityName
        publisher = $publisher
        version = $version
        package_family_name = $packageFamilyName
        package_sid = $packageSid
    }
}
$handoffPath = Join-Path $handoffRoot 'handoff.json'
$handoff | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $handoffPath -Encoding UTF8

Write-Host "Created unsigned Store candidate: $packagePath"
Write-Host "SHA256: $hash"
Write-Host 'HOLD remains until signature/Store validation and Windows GPU QA are completed.'
) { Stop-Hold 'invalid request_id' }
if ($productType -ne 'GAME_3D') { Stop-Hold 'approved identity product_type mismatch' }
if ($sourceFactory -ne '3d-game-factory') { Stop-Hold 'approved identity source_factory mismatch' }
if ($sourceRepository -ne 'shihuiarenjinba-png/3d-game-factory') { Stop-Hold 'approved identity source_repository mismatch' }
if ($sourceBranch -ne 'codex/3d-real-msix-build-path-20261027') { Stop-Hold 'approved identity source_branch mismatch' }
if ($identitySlug -ne $Slug) { Stop-Hold 'approved identity slug mismatch' }
if ($storeId -notmatch '^[A-Za-z0-9]{8,32}
if ($identityName -notmatch '^[A-Za-z][A-Za-z0-9._-]{2,49}$') { Stop-Hold 'invalid package Identity Name' }
if ($publisher -notmatch '^CN=') { Stop-Hold 'invalid Publisher subject' }
if ($version -notmatch '^\d{1,5}(\.\d{1,5}){3}$') { Stop-Hold 'invalid four-part package version' }
if ($verifiedSourceSha -notmatch '^[0-9a-f]{40}$') { Stop-Hold 'verified source SHA is missing or malformed' }
try { $evidence = [Uri]$evidenceUrl } catch { Stop-Hold 'invalid Partner Center evidence URL' }
if ($evidence.Scheme -ne 'https' -or $evidence.Host -notin @('partner.microsoft.com', 'partnercenter.microsoft.com')) {
    Stop-Hold 'untrusted Partner Center evidence URL'
}

$displayName = if ($identity.display_name) { [string]$identity.display_name } else { Require-Text $metadata 'display_name' 100 }
$publisherDisplayName = if ($identity.publisher_display_name) { [string]$identity.publisher_display_name } else { Require-Text $metadata 'publisher_display_name' 100 }
$description = Require-Text $metadata 'description' 200
$language = Require-Text $metadata 'language' 20
$minWindows = Require-Text $metadata 'min_windows_version' 32
$maxWindows = Require-Text $metadata 'max_windows_version_tested' 32
foreach ($osVersion in @($minWindows, $maxWindows)) {
    if ($osVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') { Stop-Hold 'Windows version metadata must use four-part notation' }
}

Push-Location $root
try {
    $currentHead = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentHead -notmatch '^[0-9a-f]{40}$') { Stop-Hold 'cannot resolve current Git HEAD' }
    $currentBranch = (& git symbolic-ref --quiet --short HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentBranch -ne 'codex/3d-real-msix-build-path-20261027') {
        Stop-Hold 'MSIX build requires the approved 3D Factory work branch'
    }
    # An unsigned package must never be built from a dirty/untracked product
    # while evidence incorrectly claims the clean commit HEAD as its source.
    $productChanges = @(& git status --porcelain --untracked-files=all -- ("products/" + $Slug))
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'cannot inspect product working tree' }
    if ($productChanges.Count -gt 0) {
        Stop-Hold 'product has uncommitted or untracked files; commit and review before MSIX build'
    }
    & git cat-file -e ($verifiedSourceSha + '^{commit}') 2>$null
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'verified source SHA is not present in checkout history' }
    $changed = @(& git diff --name-only ($verifiedSourceSha + '..HEAD') -- ("products/" + $Slug))
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'cannot compare product source to verified source SHA' }
    $allowedIdentityPath = "products/$Slug/store/approved-identity.json"
    $unexpected = @($changed | Where-Object { $_ -and $_ -ne $allowedIdentityPath })
    if ($unexpected.Count -gt 0) { Stop-Hold ("product changed after Identity verification: " + ($unexpected -join ', ')) }
}
finally { Pop-Location }

foreach ($asset in @('StoreLogo.png','Square150.png','Square44.png')) {
    $path = Join-Path $storeRoot $asset
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
        Stop-Hold "required Store asset is missing or empty: $asset"
    }
}

$godot = $env:GODOT_EXE
if ([string]::IsNullOrWhiteSpace($godot) -or -not (Test-Path -LiteralPath $godot -PathType Leaf)) { Stop-Hold 'GODOT_EXE is not configured' }

$outRoot = Join-Path $root $OutputDirectory
$godotOut = Join-Path $outRoot 'godot'
$layout = Join-Path $outRoot 'msix-layout'
Remove-Item -LiteralPath $godotOut -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $layout -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $godotOut, (Join-Path $layout 'Game'), (Join-Path $layout 'Assets') | Out-Null

$rawExe = Join-Path $godotOut 'game.exe'
& $godot --headless --path $productRoot --export-release 'Windows Desktop' $rawExe
if ($LASTEXITCODE -ne 0) { Stop-Hold 'Godot Windows export failed' }
if (-not (Test-Path -LiteralPath $rawExe -PathType Leaf) -or (Get-Item -LiteralPath $rawExe).Length -lt 1024) {
    Stop-Hold 'Godot export produced no usable executable'
}
$stream = [System.IO.File]::OpenRead($rawExe)
try {
    $b0 = $stream.ReadByte(); $b1 = $stream.ReadByte()
} finally { $stream.Dispose() }
if ($b0 -ne 0x4D -or $b1 -ne 0x5A) { Stop-Hold 'Godot export is not a Windows PE executable' }

Copy-Item -LiteralPath $rawExe -Destination (Join-Path $layout 'Game\game.exe')
$presetText = Get-Content -LiteralPath $presets -Raw -Encoding UTF8
if ($presetText -match '(?m)^\s*binary_format/embed_pck\s*=\s*false\s*$') {
    $rawPck = [System.IO.Path]::ChangeExtension($rawExe, '.pck')
    if (-not (Test-Path -LiteralPath $rawPck -PathType Leaf) -or (Get-Item -LiteralPath $rawPck).Length -eq 0) {
        Stop-Hold 'Godot export omitted required external PCK'
    }
    Copy-Item -LiteralPath $rawPck -Destination (Join-Path $layout 'Game\game.pck')
}

Copy-Item -LiteralPath (Join-Path $storeRoot 'StoreLogo.png') -Destination (Join-Path $layout 'Assets\StoreLogo.png')
Copy-Item -LiteralPath (Join-Path $storeRoot 'Square150.png') -Destination (Join-Path $layout 'Assets\Square150.png')
Copy-Item -LiteralPath (Join-Path $storeRoot 'Square44.png') -Destination (Join-Path $layout 'Assets\Square44.png')

$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:uap10="http://schemas.microsoft.com/appx/manifest/uap/windows10/10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  IgnorableNamespaces="uap uap10 rescap">
  <Identity Name="$(Xml-Escape $identityName)" Version="$(Xml-Escape $version)" Publisher="$(Xml-Escape $publisher)" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>$(Xml-Escape $displayName)</DisplayName>
    <PublisherDisplayName>$(Xml-Escape $publisherDisplayName)</PublisherDisplayName>
    <Description>$(Xml-Escape $description)</Description>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Resources>
    <Resource Language="$(Xml-Escape $language)" />
  </Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="$(Xml-Escape $minWindows)" MaxVersionTested="$(Xml-Escape $maxWindows)" />
  </Dependencies>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
  <Applications>
    <Application Id="Game" Executable="Game\game.exe" uap10:RuntimeBehavior="packagedClassicApp" uap10:TrustLevel="mediumIL">
      <uap:VisualElements DisplayName="$(Xml-Escape $displayName)" Description="$(Xml-Escape $description)" Square150x150Logo="Assets\Square150.png" Square44x44Logo="Assets\Square44.png" BackgroundColor="transparent" />
    </Application>
  </Applications>
</Package>
"@
$manifestPath = Join-Path $layout 'AppxManifest.xml'
[System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))

$makeAppx = Get-Command makeappx.exe -ErrorAction SilentlyContinue
if ($null -eq $makeAppx) {
    $sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $makeAppx = Get-ChildItem -LiteralPath $sdkRoot -Filter makeappx.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\makeappx\.exe$' } |
        Sort-Object FullName -Descending | Select-Object -First 1
}
if ($null -eq $makeAppx) { Stop-Hold 'MakeAppx.exe was not found in the Windows SDK' }

$packageName = "${Slug}_${version}_x64_QA_UNSIGNED.msix"
$packagePath = Join-Path $outRoot $packageName
Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
& $makeAppx.Source pack /o /v /d $layout /p $packagePath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { Stop-Hold 'MakeAppx failed to create MSIX' }

$hash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
$evidenceOut = [ordered]@{
    schema_version = '1.0'
    status = 'QA_UNSIGNED_MSIX'
    slug = $Slug
    source_sha = $currentHead
    identity_verified_source_sha = $verifiedSourceSha
    store_id = $storeId
    identity_name = $identityName
    publisher = $publisher
    version = $version
    verified_by = $verifiedBy
    evidence_url = $evidenceUrl
    msix_file = $packageName
    msix_sha256 = $hash
    signature_verified = $false
    windows_gpu_qa = 'NOT_RUN'
    store_submission = 'NOT_RUN'
}
$evidencePath = Join-Path $outRoot 'msix-evidence.json'
$evidenceOut | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $evidencePath -Encoding UTF8

# Publish a separate, strict two-file handoff for Windows-all-auto.
# The QA_UNSIGNED artifact is never a Store submission or certification claim.
$handoffRoot = Join-Path $outRoot 'handoff'
New-Item -ItemType Directory -Force -Path $handoffRoot | Out-Null
$handoffPackage = Join-Path $handoffRoot 'package.msix'
Copy-Item -LiteralPath $packagePath -Destination $handoffPackage -Force
$handoff = [ordered]@{
    schema_version = 1
    source_repository = 'https://github.com/shihuiarenjinba-png/3d-game-factory'
    source_sha = $currentHead
    type = '3d-game'
    slug = $Slug
    package = 'package.msix'
    status = 'QA_UNSIGNED'
    package_sha256 = $hash
    package_bytes = (Get-Item -LiteralPath $packagePath).Length
    identity = [ordered]@{
        name = $identityName
        publisher = $publisher
        version = $version
    }
}
$handoffPath = Join-Path $handoffRoot 'handoff.json'
$handoff | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $handoffPath -Encoding UTF8

Write-Host "Created unsigned Store candidate: $packagePath"
Write-Host "SHA256: $hash"
Write-Host 'HOLD remains until signature/Store validation and Windows GPU QA are completed.'
) { Stop-Hold 'invalid Store ID format' }
if ($identityName -notmatch '^[A-Za-z][A-Za-z0-9._-]{2,49}$') { Stop-Hold 'invalid package Identity Name' }
if ($publisher -notmatch '^CN=') { Stop-Hold 'invalid Publisher subject' }
if ($version -notmatch '^\d{1,5}(\.\d{1,5}){3}$') { Stop-Hold 'invalid four-part package version' }
if ($verifiedSourceSha -notmatch '^[0-9a-f]{40}$') { Stop-Hold 'verified source SHA is missing or malformed' }
try { $evidence = [Uri]$evidenceUrl } catch { Stop-Hold 'invalid Partner Center evidence URL' }
if ($evidence.Scheme -ne 'https' -or $evidence.Host -notin @('partner.microsoft.com', 'partnercenter.microsoft.com')) {
    Stop-Hold 'untrusted Partner Center evidence URL'
}

$displayName = if ($identity.display_name) { [string]$identity.display_name } else { Require-Text $metadata 'display_name' 100 }
$publisherDisplayName = if ($identity.publisher_display_name) { [string]$identity.publisher_display_name } else { Require-Text $metadata 'publisher_display_name' 100 }
$description = Require-Text $metadata 'description' 200
$language = Require-Text $metadata 'language' 20
$minWindows = Require-Text $metadata 'min_windows_version' 32
$maxWindows = Require-Text $metadata 'max_windows_version_tested' 32
foreach ($osVersion in @($minWindows, $maxWindows)) {
    if ($osVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') { Stop-Hold 'Windows version metadata must use four-part notation' }
}

Push-Location $root
try {
    $currentHead = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentHead -notmatch '^[0-9a-f]{40}$') { Stop-Hold 'cannot resolve current Git HEAD' }
    $currentBranch = (& git symbolic-ref --quiet --short HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentBranch -ne 'codex/3d-real-msix-build-path-20261027') {
        Stop-Hold 'MSIX build requires the approved 3D Factory work branch'
    }
    # An unsigned package must never be built from a dirty/untracked product
    # while evidence incorrectly claims the clean commit HEAD as its source.
    $productChanges = @(& git status --porcelain --untracked-files=all -- ("products/" + $Slug))
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'cannot inspect product working tree' }
    if ($productChanges.Count -gt 0) {
        Stop-Hold 'product has uncommitted or untracked files; commit and review before MSIX build'
    }
    & git cat-file -e ($verifiedSourceSha + '^{commit}') 2>$null
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'verified source SHA is not present in checkout history' }
    $changed = @(& git diff --name-only ($verifiedSourceSha + '..HEAD') -- ("products/" + $Slug))
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'cannot compare product source to verified source SHA' }
    $allowedIdentityPath = "products/$Slug/store/approved-identity.json"
    $unexpected = @($changed | Where-Object { $_ -and $_ -ne $allowedIdentityPath })
    if ($unexpected.Count -gt 0) { Stop-Hold ("product changed after Identity verification: " + ($unexpected -join ', ')) }
}
finally { Pop-Location }

foreach ($asset in @('StoreLogo.png','Square150.png','Square44.png')) {
    $path = Join-Path $storeRoot $asset
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
        Stop-Hold "required Store asset is missing or empty: $asset"
    }
}

$godot = $env:GODOT_EXE
if ([string]::IsNullOrWhiteSpace($godot) -or -not (Test-Path -LiteralPath $godot -PathType Leaf)) { Stop-Hold 'GODOT_EXE is not configured' }

$outRoot = Join-Path $root $OutputDirectory
$godotOut = Join-Path $outRoot 'godot'
$layout = Join-Path $outRoot 'msix-layout'
Remove-Item -LiteralPath $godotOut -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $layout -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $godotOut, (Join-Path $layout 'Game'), (Join-Path $layout 'Assets') | Out-Null

$rawExe = Join-Path $godotOut 'game.exe'
& $godot --headless --path $productRoot --export-release 'Windows Desktop' $rawExe
if ($LASTEXITCODE -ne 0) { Stop-Hold 'Godot Windows export failed' }
if (-not (Test-Path -LiteralPath $rawExe -PathType Leaf) -or (Get-Item -LiteralPath $rawExe).Length -lt 1024) {
    Stop-Hold 'Godot export produced no usable executable'
}
$stream = [System.IO.File]::OpenRead($rawExe)
try {
    $b0 = $stream.ReadByte(); $b1 = $stream.ReadByte()
} finally { $stream.Dispose() }
if ($b0 -ne 0x4D -or $b1 -ne 0x5A) { Stop-Hold 'Godot export is not a Windows PE executable' }

Copy-Item -LiteralPath $rawExe -Destination (Join-Path $layout 'Game\game.exe')
$presetText = Get-Content -LiteralPath $presets -Raw -Encoding UTF8
if ($presetText -match '(?m)^\s*binary_format/embed_pck\s*=\s*false\s*$') {
    $rawPck = [System.IO.Path]::ChangeExtension($rawExe, '.pck')
    if (-not (Test-Path -LiteralPath $rawPck -PathType Leaf) -or (Get-Item -LiteralPath $rawPck).Length -eq 0) {
        Stop-Hold 'Godot export omitted required external PCK'
    }
    Copy-Item -LiteralPath $rawPck -Destination (Join-Path $layout 'Game\game.pck')
}

Copy-Item -LiteralPath (Join-Path $storeRoot 'StoreLogo.png') -Destination (Join-Path $layout 'Assets\StoreLogo.png')
Copy-Item -LiteralPath (Join-Path $storeRoot 'Square150.png') -Destination (Join-Path $layout 'Assets\Square150.png')
Copy-Item -LiteralPath (Join-Path $storeRoot 'Square44.png') -Destination (Join-Path $layout 'Assets\Square44.png')

$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:uap10="http://schemas.microsoft.com/appx/manifest/uap/windows10/10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  IgnorableNamespaces="uap uap10 rescap">
  <Identity Name="$(Xml-Escape $identityName)" Version="$(Xml-Escape $version)" Publisher="$(Xml-Escape $publisher)" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>$(Xml-Escape $displayName)</DisplayName>
    <PublisherDisplayName>$(Xml-Escape $publisherDisplayName)</PublisherDisplayName>
    <Description>$(Xml-Escape $description)</Description>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Resources>
    <Resource Language="$(Xml-Escape $language)" />
  </Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="$(Xml-Escape $minWindows)" MaxVersionTested="$(Xml-Escape $maxWindows)" />
  </Dependencies>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
  <Applications>
    <Application Id="Game" Executable="Game\game.exe" uap10:RuntimeBehavior="packagedClassicApp" uap10:TrustLevel="mediumIL">
      <uap:VisualElements DisplayName="$(Xml-Escape $displayName)" Description="$(Xml-Escape $description)" Square150x150Logo="Assets\Square150.png" Square44x44Logo="Assets\Square44.png" BackgroundColor="transparent" />
    </Application>
  </Applications>
</Package>
"@
$manifestPath = Join-Path $layout 'AppxManifest.xml'
[System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))

$makeAppx = Get-Command makeappx.exe -ErrorAction SilentlyContinue
if ($null -eq $makeAppx) {
    $sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $makeAppx = Get-ChildItem -LiteralPath $sdkRoot -Filter makeappx.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\makeappx\.exe$' } |
        Sort-Object FullName -Descending | Select-Object -First 1
}
if ($null -eq $makeAppx) { Stop-Hold 'MakeAppx.exe was not found in the Windows SDK' }

$packageName = "${Slug}_${version}_x64_QA_UNSIGNED.msix"
$packagePath = Join-Path $outRoot $packageName
Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
& $makeAppx.Source pack /o /v /d $layout /p $packagePath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { Stop-Hold 'MakeAppx failed to create MSIX' }

$hash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
$evidenceOut = [ordered]@{
    schema_version = '1.0'
    status = 'QA_UNSIGNED_MSIX'
    slug = $Slug
    source_sha = $currentHead
    identity_verified_source_sha = $verifiedSourceSha
    store_id = $storeId
    identity_name = $identityName
    publisher = $publisher
    version = $version
    verified_by = $verifiedBy
    evidence_url = $evidenceUrl
    msix_file = $packageName
    msix_sha256 = $hash
    signature_verified = $false
    windows_gpu_qa = 'NOT_RUN'
    store_submission = 'NOT_RUN'
}
$evidencePath = Join-Path $outRoot 'msix-evidence.json'
$evidenceOut | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $evidencePath -Encoding UTF8

# Publish a separate, strict two-file handoff for Windows-all-auto.
# The QA_UNSIGNED artifact is never a Store submission or certification claim.
$handoffRoot = Join-Path $outRoot 'handoff'
New-Item -ItemType Directory -Force -Path $handoffRoot | Out-Null
$handoffPackage = Join-Path $handoffRoot 'package.msix'
Copy-Item -LiteralPath $packagePath -Destination $handoffPackage -Force
$handoff = [ordered]@{
    schema_version = 1
    source_repository = 'https://github.com/shihuiarenjinba-png/3d-game-factory'
    source_sha = $currentHead
    type = '3d-game'
    slug = $Slug
    package = 'package.msix'
    status = 'QA_UNSIGNED'
    package_sha256 = $hash
    package_bytes = (Get-Item -LiteralPath $packagePath).Length
    identity = [ordered]@{
        name = $identityName
        publisher = $publisher
        version = $version
    }
}
$handoffPath = Join-Path $handoffRoot 'handoff.json'
$handoff | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $handoffPath -Encoding UTF8

Write-Host "Created unsigned Store candidate: $packagePath"
Write-Host "SHA256: $hash"
Write-Host 'HOLD remains until signature/Store validation and Windows GPU QA are completed.'
) { Stop-Hold 'verified source SHA is missing or malformed' }
if ($expectedHeadSha -ne $verifiedSourceSha) { Stop-Hold 'expected HEAD SHA differs from verified source SHA' }
if ($localPackageSha256 -notmatch '^[0-9a-f]{64}
try { $evidence = [Uri]$evidenceUrl } catch { Stop-Hold 'invalid Partner Center evidence URL' }
if ($evidence.Scheme -ne 'https' -or $evidence.Host -notin @('partner.microsoft.com', 'partnercenter.microsoft.com')) {
    Stop-Hold 'untrusted Partner Center evidence URL'
}

$displayName = if ($identity.display_name) { [string]$identity.display_name } else { Require-Text $metadata 'display_name' 100 }
$publisherDisplayName = if ($identity.publisher_display_name) { [string]$identity.publisher_display_name } else { Require-Text $metadata 'publisher_display_name' 100 }
$description = Require-Text $metadata 'description' 200
$language = Require-Text $metadata 'language' 20
$minWindows = Require-Text $metadata 'min_windows_version' 32
$maxWindows = Require-Text $metadata 'max_windows_version_tested' 32
foreach ($osVersion in @($minWindows, $maxWindows)) {
    if ($osVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') { Stop-Hold 'Windows version metadata must use four-part notation' }
}

Push-Location $root
try {
    $currentHead = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentHead -notmatch '^[0-9a-f]{40}$') { Stop-Hold 'cannot resolve current Git HEAD' }
    $currentBranch = (& git symbolic-ref --quiet --short HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentBranch -ne 'codex/3d-real-msix-build-path-20261027') {
        Stop-Hold 'MSIX build requires the approved 3D Factory work branch'
    }
    # An unsigned package must never be built from a dirty/untracked product
    # while evidence incorrectly claims the clean commit HEAD as its source.
    $productChanges = @(& git status --porcelain --untracked-files=all -- ("products/" + $Slug))
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'cannot inspect product working tree' }
    if ($productChanges.Count -gt 0) {
        Stop-Hold 'product has uncommitted or untracked files; commit and review before MSIX build'
    }
    & git cat-file -e ($verifiedSourceSha + '^{commit}') 2>$null
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'verified source SHA is not present in checkout history' }
    $changed = @(& git diff --name-only ($verifiedSourceSha + '..HEAD') -- ("products/" + $Slug))
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'cannot compare product source to verified source SHA' }
    $allowedIdentityPath = "products/$Slug/store/approved-identity.json"
    $unexpected = @($changed | Where-Object { $_ -and $_ -ne $allowedIdentityPath })
    if ($unexpected.Count -gt 0) { Stop-Hold ("product changed after Identity verification: " + ($unexpected -join ', ')) }
}
finally { Pop-Location }

foreach ($asset in @('StoreLogo.png','Square150.png','Square44.png')) {
    $path = Join-Path $storeRoot $asset
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
        Stop-Hold "required Store asset is missing or empty: $asset"
    }
}

$godot = $env:GODOT_EXE
if ([string]::IsNullOrWhiteSpace($godot) -or -not (Test-Path -LiteralPath $godot -PathType Leaf)) { Stop-Hold 'GODOT_EXE is not configured' }

$outRoot = Join-Path $root $OutputDirectory
$godotOut = Join-Path $outRoot 'godot'
$layout = Join-Path $outRoot 'msix-layout'
Remove-Item -LiteralPath $godotOut -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $layout -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $godotOut, (Join-Path $layout 'Game'), (Join-Path $layout 'Assets') | Out-Null

$rawExe = Join-Path $godotOut 'game.exe'
& $godot --headless --path $productRoot --export-release 'Windows Desktop' $rawExe
if ($LASTEXITCODE -ne 0) { Stop-Hold 'Godot Windows export failed' }
if (-not (Test-Path -LiteralPath $rawExe -PathType Leaf) -or (Get-Item -LiteralPath $rawExe).Length -lt 1024) {
    Stop-Hold 'Godot export produced no usable executable'
}
$stream = [System.IO.File]::OpenRead($rawExe)
try {
    $b0 = $stream.ReadByte(); $b1 = $stream.ReadByte()
} finally { $stream.Dispose() }
if ($b0 -ne 0x4D -or $b1 -ne 0x5A) { Stop-Hold 'Godot export is not a Windows PE executable' }

Copy-Item -LiteralPath $rawExe -Destination (Join-Path $layout 'Game\game.exe')
$presetText = Get-Content -LiteralPath $presets -Raw -Encoding UTF8
if ($presetText -match '(?m)^\s*binary_format/embed_pck\s*=\s*false\s*$') {
    $rawPck = [System.IO.Path]::ChangeExtension($rawExe, '.pck')
    if (-not (Test-Path -LiteralPath $rawPck -PathType Leaf) -or (Get-Item -LiteralPath $rawPck).Length -eq 0) {
        Stop-Hold 'Godot export omitted required external PCK'
    }
    Copy-Item -LiteralPath $rawPck -Destination (Join-Path $layout 'Game\game.pck')
}

Copy-Item -LiteralPath (Join-Path $storeRoot 'StoreLogo.png') -Destination (Join-Path $layout 'Assets\StoreLogo.png')
Copy-Item -LiteralPath (Join-Path $storeRoot 'Square150.png') -Destination (Join-Path $layout 'Assets\Square150.png')
Copy-Item -LiteralPath (Join-Path $storeRoot 'Square44.png') -Destination (Join-Path $layout 'Assets\Square44.png')

$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:uap10="http://schemas.microsoft.com/appx/manifest/uap/windows10/10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  IgnorableNamespaces="uap uap10 rescap">
  <Identity Name="$(Xml-Escape $identityName)" Version="$(Xml-Escape $version)" Publisher="$(Xml-Escape $publisher)" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>$(Xml-Escape $displayName)</DisplayName>
    <PublisherDisplayName>$(Xml-Escape $publisherDisplayName)</PublisherDisplayName>
    <Description>$(Xml-Escape $description)</Description>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Resources>
    <Resource Language="$(Xml-Escape $language)" />
  </Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="$(Xml-Escape $minWindows)" MaxVersionTested="$(Xml-Escape $maxWindows)" />
  </Dependencies>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
  <Applications>
    <Application Id="Game" Executable="Game\game.exe" uap10:RuntimeBehavior="packagedClassicApp" uap10:TrustLevel="mediumIL">
      <uap:VisualElements DisplayName="$(Xml-Escape $displayName)" Description="$(Xml-Escape $description)" Square150x150Logo="Assets\Square150.png" Square44x44Logo="Assets\Square44.png" BackgroundColor="transparent" />
    </Application>
  </Applications>
</Package>
"@
$manifestPath = Join-Path $layout 'AppxManifest.xml'
[System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))

$makeAppx = Get-Command makeappx.exe -ErrorAction SilentlyContinue
if ($null -eq $makeAppx) {
    $sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $makeAppx = Get-ChildItem -LiteralPath $sdkRoot -Filter makeappx.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\makeappx\.exe$' } |
        Sort-Object FullName -Descending | Select-Object -First 1
}
if ($null -eq $makeAppx) { Stop-Hold 'MakeAppx.exe was not found in the Windows SDK' }

$packageName = "${Slug}_${version}_x64_QA_UNSIGNED.msix"
$packagePath = Join-Path $outRoot $packageName
Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
& $makeAppx.Source pack /o /v /d $layout /p $packagePath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { Stop-Hold 'MakeAppx failed to create MSIX' }

$hash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
$evidenceOut = [ordered]@{
    schema_version = '1.0'
    status = 'QA_UNSIGNED_MSIX'
    slug = $Slug
    source_sha = $currentHead
    identity_verified_source_sha = $verifiedSourceSha
    store_id = $storeId
    identity_name = $identityName
    publisher = $publisher
    version = $version
    verified_by = $verifiedBy
    evidence_url = $evidenceUrl
    msix_file = $packageName
    msix_sha256 = $hash
    signature_verified = $false
    windows_gpu_qa = 'NOT_RUN'
    store_submission = 'NOT_RUN'
}
$evidencePath = Join-Path $outRoot 'msix-evidence.json'
$evidenceOut | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $evidencePath -Encoding UTF8

# Publish a separate, strict two-file handoff for Windows-all-auto.
# The QA_UNSIGNED artifact is never a Store submission or certification claim.
$handoffRoot = Join-Path $outRoot 'handoff'
New-Item -ItemType Directory -Force -Path $handoffRoot | Out-Null
$handoffPackage = Join-Path $handoffRoot 'package.msix'
Copy-Item -LiteralPath $packagePath -Destination $handoffPackage -Force
$handoff = [ordered]@{
    schema_version = 1
    source_repository = 'https://github.com/shihuiarenjinba-png/3d-game-factory'
    source_sha = $currentHead
    type = '3d-game'
    slug = $Slug
    package = 'package.msix'
    status = 'QA_UNSIGNED'
    package_sha256 = $hash
    package_bytes = (Get-Item -LiteralPath $packagePath).Length
    identity = [ordered]@{
        name = $identityName
        publisher = $publisher
        version = $version
    }
}
$handoffPath = Join-Path $handoffRoot 'handoff.json'
$handoff | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $handoffPath -Encoding UTF8

Write-Host "Created unsigned Store candidate: $packagePath"
Write-Host "SHA256: $hash"
Write-Host 'HOLD remains until signature/Store validation and Windows GPU QA are completed.'
) { Stop-Hold 'invalid request_id' }
if ($productType -ne 'GAME_3D') { Stop-Hold 'approved identity product_type mismatch' }
if ($sourceFactory -ne '3d-game-factory') { Stop-Hold 'approved identity source_factory mismatch' }
if ($sourceRepository -ne 'shihuiarenjinba-png/3d-game-factory') { Stop-Hold 'approved identity source_repository mismatch' }
if ($sourceBranch -ne 'codex/3d-real-msix-build-path-20261027') { Stop-Hold 'approved identity source_branch mismatch' }
if ($identitySlug -ne $Slug) { Stop-Hold 'approved identity slug mismatch' }
if ($storeId -notmatch '^[A-Za-z0-9]{8,32}
if ($identityName -notmatch '^[A-Za-z][A-Za-z0-9._-]{2,49}$') { Stop-Hold 'invalid package Identity Name' }
if ($publisher -notmatch '^CN=') { Stop-Hold 'invalid Publisher subject' }
if ($version -notmatch '^\d{1,5}(\.\d{1,5}){3}$') { Stop-Hold 'invalid four-part package version' }
if ($verifiedSourceSha -notmatch '^[0-9a-f]{40}$') { Stop-Hold 'verified source SHA is missing or malformed' }
try { $evidence = [Uri]$evidenceUrl } catch { Stop-Hold 'invalid Partner Center evidence URL' }
if ($evidence.Scheme -ne 'https' -or $evidence.Host -notin @('partner.microsoft.com', 'partnercenter.microsoft.com')) {
    Stop-Hold 'untrusted Partner Center evidence URL'
}

$displayName = if ($identity.display_name) { [string]$identity.display_name } else { Require-Text $metadata 'display_name' 100 }
$publisherDisplayName = if ($identity.publisher_display_name) { [string]$identity.publisher_display_name } else { Require-Text $metadata 'publisher_display_name' 100 }
$description = Require-Text $metadata 'description' 200
$language = Require-Text $metadata 'language' 20
$minWindows = Require-Text $metadata 'min_windows_version' 32
$maxWindows = Require-Text $metadata 'max_windows_version_tested' 32
foreach ($osVersion in @($minWindows, $maxWindows)) {
    if ($osVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') { Stop-Hold 'Windows version metadata must use four-part notation' }
}

Push-Location $root
try {
    $currentHead = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentHead -notmatch '^[0-9a-f]{40}$') { Stop-Hold 'cannot resolve current Git HEAD' }
    $currentBranch = (& git symbolic-ref --quiet --short HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentBranch -ne 'codex/3d-real-msix-build-path-20261027') {
        Stop-Hold 'MSIX build requires the approved 3D Factory work branch'
    }
    # An unsigned package must never be built from a dirty/untracked product
    # while evidence incorrectly claims the clean commit HEAD as its source.
    $productChanges = @(& git status --porcelain --untracked-files=all -- ("products/" + $Slug))
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'cannot inspect product working tree' }
    if ($productChanges.Count -gt 0) {
        Stop-Hold 'product has uncommitted or untracked files; commit and review before MSIX build'
    }
    & git cat-file -e ($verifiedSourceSha + '^{commit}') 2>$null
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'verified source SHA is not present in checkout history' }
    $changed = @(& git diff --name-only ($verifiedSourceSha + '..HEAD') -- ("products/" + $Slug))
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'cannot compare product source to verified source SHA' }
    $allowedIdentityPath = "products/$Slug/store/approved-identity.json"
    $unexpected = @($changed | Where-Object { $_ -and $_ -ne $allowedIdentityPath })
    if ($unexpected.Count -gt 0) { Stop-Hold ("product changed after Identity verification: " + ($unexpected -join ', ')) }
}
finally { Pop-Location }

foreach ($asset in @('StoreLogo.png','Square150.png','Square44.png')) {
    $path = Join-Path $storeRoot $asset
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
        Stop-Hold "required Store asset is missing or empty: $asset"
    }
}

$godot = $env:GODOT_EXE
if ([string]::IsNullOrWhiteSpace($godot) -or -not (Test-Path -LiteralPath $godot -PathType Leaf)) { Stop-Hold 'GODOT_EXE is not configured' }

$outRoot = Join-Path $root $OutputDirectory
$godotOut = Join-Path $outRoot 'godot'
$layout = Join-Path $outRoot 'msix-layout'
Remove-Item -LiteralPath $godotOut -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $layout -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $godotOut, (Join-Path $layout 'Game'), (Join-Path $layout 'Assets') | Out-Null

$rawExe = Join-Path $godotOut 'game.exe'
& $godot --headless --path $productRoot --export-release 'Windows Desktop' $rawExe
if ($LASTEXITCODE -ne 0) { Stop-Hold 'Godot Windows export failed' }
if (-not (Test-Path -LiteralPath $rawExe -PathType Leaf) -or (Get-Item -LiteralPath $rawExe).Length -lt 1024) {
    Stop-Hold 'Godot export produced no usable executable'
}
$stream = [System.IO.File]::OpenRead($rawExe)
try {
    $b0 = $stream.ReadByte(); $b1 = $stream.ReadByte()
} finally { $stream.Dispose() }
if ($b0 -ne 0x4D -or $b1 -ne 0x5A) { Stop-Hold 'Godot export is not a Windows PE executable' }

Copy-Item -LiteralPath $rawExe -Destination (Join-Path $layout 'Game\game.exe')
$presetText = Get-Content -LiteralPath $presets -Raw -Encoding UTF8
if ($presetText -match '(?m)^\s*binary_format/embed_pck\s*=\s*false\s*$') {
    $rawPck = [System.IO.Path]::ChangeExtension($rawExe, '.pck')
    if (-not (Test-Path -LiteralPath $rawPck -PathType Leaf) -or (Get-Item -LiteralPath $rawPck).Length -eq 0) {
        Stop-Hold 'Godot export omitted required external PCK'
    }
    Copy-Item -LiteralPath $rawPck -Destination (Join-Path $layout 'Game\game.pck')
}

Copy-Item -LiteralPath (Join-Path $storeRoot 'StoreLogo.png') -Destination (Join-Path $layout 'Assets\StoreLogo.png')
Copy-Item -LiteralPath (Join-Path $storeRoot 'Square150.png') -Destination (Join-Path $layout 'Assets\Square150.png')
Copy-Item -LiteralPath (Join-Path $storeRoot 'Square44.png') -Destination (Join-Path $layout 'Assets\Square44.png')

$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:uap10="http://schemas.microsoft.com/appx/manifest/uap/windows10/10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  IgnorableNamespaces="uap uap10 rescap">
  <Identity Name="$(Xml-Escape $identityName)" Version="$(Xml-Escape $version)" Publisher="$(Xml-Escape $publisher)" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>$(Xml-Escape $displayName)</DisplayName>
    <PublisherDisplayName>$(Xml-Escape $publisherDisplayName)</PublisherDisplayName>
    <Description>$(Xml-Escape $description)</Description>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Resources>
    <Resource Language="$(Xml-Escape $language)" />
  </Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="$(Xml-Escape $minWindows)" MaxVersionTested="$(Xml-Escape $maxWindows)" />
  </Dependencies>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
  <Applications>
    <Application Id="Game" Executable="Game\game.exe" uap10:RuntimeBehavior="packagedClassicApp" uap10:TrustLevel="mediumIL">
      <uap:VisualElements DisplayName="$(Xml-Escape $displayName)" Description="$(Xml-Escape $description)" Square150x150Logo="Assets\Square150.png" Square44x44Logo="Assets\Square44.png" BackgroundColor="transparent" />
    </Application>
  </Applications>
</Package>
"@
$manifestPath = Join-Path $layout 'AppxManifest.xml'
[System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))

$makeAppx = Get-Command makeappx.exe -ErrorAction SilentlyContinue
if ($null -eq $makeAppx) {
    $sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $makeAppx = Get-ChildItem -LiteralPath $sdkRoot -Filter makeappx.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\makeappx\.exe$' } |
        Sort-Object FullName -Descending | Select-Object -First 1
}
if ($null -eq $makeAppx) { Stop-Hold 'MakeAppx.exe was not found in the Windows SDK' }

$packageName = "${Slug}_${version}_x64_QA_UNSIGNED.msix"
$packagePath = Join-Path $outRoot $packageName
Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
& $makeAppx.Source pack /o /v /d $layout /p $packagePath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { Stop-Hold 'MakeAppx failed to create MSIX' }

$hash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
$evidenceOut = [ordered]@{
    schema_version = '1.0'
    status = 'QA_UNSIGNED_MSIX'
    slug = $Slug
    source_sha = $currentHead
    identity_verified_source_sha = $verifiedSourceSha
    store_id = $storeId
    identity_name = $identityName
    publisher = $publisher
    version = $version
    verified_by = $verifiedBy
    evidence_url = $evidenceUrl
    msix_file = $packageName
    msix_sha256 = $hash
    signature_verified = $false
    windows_gpu_qa = 'NOT_RUN'
    store_submission = 'NOT_RUN'
}
$evidencePath = Join-Path $outRoot 'msix-evidence.json'
$evidenceOut | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $evidencePath -Encoding UTF8

# Publish a separate, strict two-file handoff for Windows-all-auto.
# The QA_UNSIGNED artifact is never a Store submission or certification claim.
$handoffRoot = Join-Path $outRoot 'handoff'
New-Item -ItemType Directory -Force -Path $handoffRoot | Out-Null
$handoffPackage = Join-Path $handoffRoot 'package.msix'
Copy-Item -LiteralPath $packagePath -Destination $handoffPackage -Force
$handoff = [ordered]@{
    schema_version = 1
    source_repository = 'https://github.com/shihuiarenjinba-png/3d-game-factory'
    source_sha = $currentHead
    type = '3d-game'
    slug = $Slug
    package = 'package.msix'
    status = 'QA_UNSIGNED'
    package_sha256 = $hash
    package_bytes = (Get-Item -LiteralPath $packagePath).Length
    identity = [ordered]@{
        name = $identityName
        publisher = $publisher
        version = $version
    }
}
$handoffPath = Join-Path $handoffRoot 'handoff.json'
$handoff | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $handoffPath -Encoding UTF8

Write-Host "Created unsigned Store candidate: $packagePath"
Write-Host "SHA256: $hash"
Write-Host 'HOLD remains until signature/Store validation and Windows GPU QA are completed.'
) { Stop-Hold 'invalid Store ID format' }
if ($identityName -notmatch '^[A-Za-z][A-Za-z0-9._-]{2,49}$') { Stop-Hold 'invalid package Identity Name' }
if ($publisher -notmatch '^CN=') { Stop-Hold 'invalid Publisher subject' }
if ($version -notmatch '^\d{1,5}(\.\d{1,5}){3}$') { Stop-Hold 'invalid four-part package version' }
if ($verifiedSourceSha -notmatch '^[0-9a-f]{40}$') { Stop-Hold 'verified source SHA is missing or malformed' }
try { $evidence = [Uri]$evidenceUrl } catch { Stop-Hold 'invalid Partner Center evidence URL' }
if ($evidence.Scheme -ne 'https' -or $evidence.Host -notin @('partner.microsoft.com', 'partnercenter.microsoft.com')) {
    Stop-Hold 'untrusted Partner Center evidence URL'
}

$displayName = if ($identity.display_name) { [string]$identity.display_name } else { Require-Text $metadata 'display_name' 100 }
$publisherDisplayName = if ($identity.publisher_display_name) { [string]$identity.publisher_display_name } else { Require-Text $metadata 'publisher_display_name' 100 }
$description = Require-Text $metadata 'description' 200
$language = Require-Text $metadata 'language' 20
$minWindows = Require-Text $metadata 'min_windows_version' 32
$maxWindows = Require-Text $metadata 'max_windows_version_tested' 32
foreach ($osVersion in @($minWindows, $maxWindows)) {
    if ($osVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') { Stop-Hold 'Windows version metadata must use four-part notation' }
}

Push-Location $root
try {
    $currentHead = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentHead -notmatch '^[0-9a-f]{40}$') { Stop-Hold 'cannot resolve current Git HEAD' }
    $currentBranch = (& git symbolic-ref --quiet --short HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentBranch -ne 'codex/3d-real-msix-build-path-20261027') {
        Stop-Hold 'MSIX build requires the approved 3D Factory work branch'
    }
    # An unsigned package must never be built from a dirty/untracked product
    # while evidence incorrectly claims the clean commit HEAD as its source.
    $productChanges = @(& git status --porcelain --untracked-files=all -- ("products/" + $Slug))
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'cannot inspect product working tree' }
    if ($productChanges.Count -gt 0) {
        Stop-Hold 'product has uncommitted or untracked files; commit and review before MSIX build'
    }
    & git cat-file -e ($verifiedSourceSha + '^{commit}') 2>$null
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'verified source SHA is not present in checkout history' }
    $changed = @(& git diff --name-only ($verifiedSourceSha + '..HEAD') -- ("products/" + $Slug))
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'cannot compare product source to verified source SHA' }
    $allowedIdentityPath = "products/$Slug/store/approved-identity.json"
    $unexpected = @($changed | Where-Object { $_ -and $_ -ne $allowedIdentityPath })
    if ($unexpected.Count -gt 0) { Stop-Hold ("product changed after Identity verification: " + ($unexpected -join ', ')) }
}
finally { Pop-Location }

foreach ($asset in @('StoreLogo.png','Square150.png','Square44.png')) {
    $path = Join-Path $storeRoot $asset
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
        Stop-Hold "required Store asset is missing or empty: $asset"
    }
}

$godot = $env:GODOT_EXE
if ([string]::IsNullOrWhiteSpace($godot) -or -not (Test-Path -LiteralPath $godot -PathType Leaf)) { Stop-Hold 'GODOT_EXE is not configured' }

$outRoot = Join-Path $root $OutputDirectory
$godotOut = Join-Path $outRoot 'godot'
$layout = Join-Path $outRoot 'msix-layout'
Remove-Item -LiteralPath $godotOut -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $layout -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $godotOut, (Join-Path $layout 'Game'), (Join-Path $layout 'Assets') | Out-Null

$rawExe = Join-Path $godotOut 'game.exe'
& $godot --headless --path $productRoot --export-release 'Windows Desktop' $rawExe
if ($LASTEXITCODE -ne 0) { Stop-Hold 'Godot Windows export failed' }
if (-not (Test-Path -LiteralPath $rawExe -PathType Leaf) -or (Get-Item -LiteralPath $rawExe).Length -lt 1024) {
    Stop-Hold 'Godot export produced no usable executable'
}
$stream = [System.IO.File]::OpenRead($rawExe)
try {
    $b0 = $stream.ReadByte(); $b1 = $stream.ReadByte()
} finally { $stream.Dispose() }
if ($b0 -ne 0x4D -or $b1 -ne 0x5A) { Stop-Hold 'Godot export is not a Windows PE executable' }

Copy-Item -LiteralPath $rawExe -Destination (Join-Path $layout 'Game\game.exe')
$presetText = Get-Content -LiteralPath $presets -Raw -Encoding UTF8
if ($presetText -match '(?m)^\s*binary_format/embed_pck\s*=\s*false\s*$') {
    $rawPck = [System.IO.Path]::ChangeExtension($rawExe, '.pck')
    if (-not (Test-Path -LiteralPath $rawPck -PathType Leaf) -or (Get-Item -LiteralPath $rawPck).Length -eq 0) {
        Stop-Hold 'Godot export omitted required external PCK'
    }
    Copy-Item -LiteralPath $rawPck -Destination (Join-Path $layout 'Game\game.pck')
}

Copy-Item -LiteralPath (Join-Path $storeRoot 'StoreLogo.png') -Destination (Join-Path $layout 'Assets\StoreLogo.png')
Copy-Item -LiteralPath (Join-Path $storeRoot 'Square150.png') -Destination (Join-Path $layout 'Assets\Square150.png')
Copy-Item -LiteralPath (Join-Path $storeRoot 'Square44.png') -Destination (Join-Path $layout 'Assets\Square44.png')

$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:uap10="http://schemas.microsoft.com/appx/manifest/uap/windows10/10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  IgnorableNamespaces="uap uap10 rescap">
  <Identity Name="$(Xml-Escape $identityName)" Version="$(Xml-Escape $version)" Publisher="$(Xml-Escape $publisher)" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>$(Xml-Escape $displayName)</DisplayName>
    <PublisherDisplayName>$(Xml-Escape $publisherDisplayName)</PublisherDisplayName>
    <Description>$(Xml-Escape $description)</Description>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Resources>
    <Resource Language="$(Xml-Escape $language)" />
  </Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="$(Xml-Escape $minWindows)" MaxVersionTested="$(Xml-Escape $maxWindows)" />
  </Dependencies>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
  <Applications>
    <Application Id="Game" Executable="Game\game.exe" uap10:RuntimeBehavior="packagedClassicApp" uap10:TrustLevel="mediumIL">
      <uap:VisualElements DisplayName="$(Xml-Escape $displayName)" Description="$(Xml-Escape $description)" Square150x150Logo="Assets\Square150.png" Square44x44Logo="Assets\Square44.png" BackgroundColor="transparent" />
    </Application>
  </Applications>
</Package>
"@
$manifestPath = Join-Path $layout 'AppxManifest.xml'
[System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))

$makeAppx = Get-Command makeappx.exe -ErrorAction SilentlyContinue
if ($null -eq $makeAppx) {
    $sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $makeAppx = Get-ChildItem -LiteralPath $sdkRoot -Filter makeappx.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\makeappx\.exe$' } |
        Sort-Object FullName -Descending | Select-Object -First 1
}
if ($null -eq $makeAppx) { Stop-Hold 'MakeAppx.exe was not found in the Windows SDK' }

$packageName = "${Slug}_${version}_x64_QA_UNSIGNED.msix"
$packagePath = Join-Path $outRoot $packageName
Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
& $makeAppx.Source pack /o /v /d $layout /p $packagePath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { Stop-Hold 'MakeAppx failed to create MSIX' }

$hash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
$evidenceOut = [ordered]@{
    schema_version = '1.0'
    status = 'QA_UNSIGNED_MSIX'
    slug = $Slug
    source_sha = $currentHead
    identity_verified_source_sha = $verifiedSourceSha
    store_id = $storeId
    identity_name = $identityName
    publisher = $publisher
    version = $version
    verified_by = $verifiedBy
    evidence_url = $evidenceUrl
    msix_file = $packageName
    msix_sha256 = $hash
    signature_verified = $false
    windows_gpu_qa = 'NOT_RUN'
    store_submission = 'NOT_RUN'
}
$evidencePath = Join-Path $outRoot 'msix-evidence.json'
$evidenceOut | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $evidencePath -Encoding UTF8

# Publish a separate, strict two-file handoff for Windows-all-auto.
# The QA_UNSIGNED artifact is never a Store submission or certification claim.
$handoffRoot = Join-Path $outRoot 'handoff'
New-Item -ItemType Directory -Force -Path $handoffRoot | Out-Null
$handoffPackage = Join-Path $handoffRoot 'package.msix'
Copy-Item -LiteralPath $packagePath -Destination $handoffPackage -Force
$handoff = [ordered]@{
    schema_version = 1
    source_repository = 'https://github.com/shihuiarenjinba-png/3d-game-factory'
    source_sha = $currentHead
    type = '3d-game'
    slug = $Slug
    package = 'package.msix'
    status = 'QA_UNSIGNED'
    package_sha256 = $hash
    package_bytes = (Get-Item -LiteralPath $packagePath).Length
    identity = [ordered]@{
        name = $identityName
        publisher = $publisher
        version = $version
    }
}
$handoffPath = Join-Path $handoffRoot 'handoff.json'
$handoff | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $handoffPath -Encoding UTF8

Write-Host "Created unsigned Store candidate: $packagePath"
Write-Host "SHA256: $hash"
Write-Host 'HOLD remains until signature/Store validation and Windows GPU QA are completed.'
) { Stop-Hold 'local package SHA-256 is malformed' }
if ($localPackageKind -notin @('exe','msix','appx')) { Stop-Hold 'local package kind is invalid' }
if (-not $packageSid.StartsWith('S-1-15-2-')) { Stop-Hold 'official Package SID is malformed' }
try { $evidence = [Uri]$evidenceUrl } catch { Stop-Hold 'invalid Partner Center evidence URL' }
if ($evidence.Scheme -ne 'https' -or $evidence.Host -notin @('partner.microsoft.com', 'partnercenter.microsoft.com')) {
    Stop-Hold 'untrusted Partner Center evidence URL'
}

$displayName = if ($identity.display_name) { [string]$identity.display_name } else { Require-Text $metadata 'display_name' 100 }
$publisherDisplayName = if ($identity.publisher_display_name) { [string]$identity.publisher_display_name } else { Require-Text $metadata 'publisher_display_name' 100 }
$description = Require-Text $metadata 'description' 200
$language = Require-Text $metadata 'language' 20
$minWindows = Require-Text $metadata 'min_windows_version' 32
$maxWindows = Require-Text $metadata 'max_windows_version_tested' 32
foreach ($osVersion in @($minWindows, $maxWindows)) {
    if ($osVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') { Stop-Hold 'Windows version metadata must use four-part notation' }
}

Push-Location $root
try {
    $currentHead = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentHead -notmatch '^[0-9a-f]{40}$') { Stop-Hold 'cannot resolve current Git HEAD' }
    $currentBranch = (& git symbolic-ref --quiet --short HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentBranch -ne 'codex/3d-real-msix-build-path-20261027') {
        Stop-Hold 'MSIX build requires the approved 3D Factory work branch'
    }
    # An unsigned package must never be built from a dirty/untracked product
    # while evidence incorrectly claims the clean commit HEAD as its source.
    $productChanges = @(& git status --porcelain --untracked-files=all -- ("products/" + $Slug))
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'cannot inspect product working tree' }
    if ($productChanges.Count -gt 0) {
        Stop-Hold 'product has uncommitted or untracked files; commit and review before MSIX build'
    }
    & git cat-file -e ($verifiedSourceSha + '^{commit}') 2>$null
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'verified source SHA is not present in checkout history' }
    $changed = @(& git diff --name-only ($verifiedSourceSha + '..HEAD') -- ("products/" + $Slug))
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'cannot compare product source to verified source SHA' }
    $allowedIdentityPath = "products/$Slug/store/approved-identity.json"
    $unexpected = @($changed | Where-Object { $_ -and $_ -ne $allowedIdentityPath })
    if ($unexpected.Count -gt 0) { Stop-Hold ("product changed after Identity verification: " + ($unexpected -join ', ')) }
}
finally { Pop-Location }

foreach ($asset in @('StoreLogo.png','Square150.png','Square44.png')) {
    $path = Join-Path $storeRoot $asset
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
        Stop-Hold "required Store asset is missing or empty: $asset"
    }
}

$godot = $env:GODOT_EXE
if ([string]::IsNullOrWhiteSpace($godot) -or -not (Test-Path -LiteralPath $godot -PathType Leaf)) { Stop-Hold 'GODOT_EXE is not configured' }

$outRoot = Join-Path $root $OutputDirectory
$godotOut = Join-Path $outRoot 'godot'
$layout = Join-Path $outRoot 'msix-layout'
Remove-Item -LiteralPath $godotOut -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $layout -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $godotOut, (Join-Path $layout 'Game'), (Join-Path $layout 'Assets') | Out-Null

$rawExe = Join-Path $godotOut 'game.exe'
& $godot --headless --path $productRoot --export-release 'Windows Desktop' $rawExe
if ($LASTEXITCODE -ne 0) { Stop-Hold 'Godot Windows export failed' }
if (-not (Test-Path -LiteralPath $rawExe -PathType Leaf) -or (Get-Item -LiteralPath $rawExe).Length -lt 1024) {
    Stop-Hold 'Godot export produced no usable executable'
}
$stream = [System.IO.File]::OpenRead($rawExe)
try {
    $b0 = $stream.ReadByte(); $b1 = $stream.ReadByte()
} finally { $stream.Dispose() }
if ($b0 -ne 0x4D -or $b1 -ne 0x5A) { Stop-Hold 'Godot export is not a Windows PE executable' }

Copy-Item -LiteralPath $rawExe -Destination (Join-Path $layout 'Game\game.exe')
$presetText = Get-Content -LiteralPath $presets -Raw -Encoding UTF8
if ($presetText -match '(?m)^\s*binary_format/embed_pck\s*=\s*false\s*$') {
    $rawPck = [System.IO.Path]::ChangeExtension($rawExe, '.pck')
    if (-not (Test-Path -LiteralPath $rawPck -PathType Leaf) -or (Get-Item -LiteralPath $rawPck).Length -eq 0) {
        Stop-Hold 'Godot export omitted required external PCK'
    }
    Copy-Item -LiteralPath $rawPck -Destination (Join-Path $layout 'Game\game.pck')
}

Copy-Item -LiteralPath (Join-Path $storeRoot 'StoreLogo.png') -Destination (Join-Path $layout 'Assets\StoreLogo.png')
Copy-Item -LiteralPath (Join-Path $storeRoot 'Square150.png') -Destination (Join-Path $layout 'Assets\Square150.png')
Copy-Item -LiteralPath (Join-Path $storeRoot 'Square44.png') -Destination (Join-Path $layout 'Assets\Square44.png')

$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:uap10="http://schemas.microsoft.com/appx/manifest/uap/windows10/10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  IgnorableNamespaces="uap uap10 rescap">
  <Identity Name="$(Xml-Escape $identityName)" Version="$(Xml-Escape $version)" Publisher="$(Xml-Escape $publisher)" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>$(Xml-Escape $displayName)</DisplayName>
    <PublisherDisplayName>$(Xml-Escape $publisherDisplayName)</PublisherDisplayName>
    <Description>$(Xml-Escape $description)</Description>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Resources>
    <Resource Language="$(Xml-Escape $language)" />
  </Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="$(Xml-Escape $minWindows)" MaxVersionTested="$(Xml-Escape $maxWindows)" />
  </Dependencies>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
  <Applications>
    <Application Id="Game" Executable="Game\game.exe" uap10:RuntimeBehavior="packagedClassicApp" uap10:TrustLevel="mediumIL">
      <uap:VisualElements DisplayName="$(Xml-Escape $displayName)" Description="$(Xml-Escape $description)" Square150x150Logo="Assets\Square150.png" Square44x44Logo="Assets\Square44.png" BackgroundColor="transparent" />
    </Application>
  </Applications>
</Package>
"@
$manifestPath = Join-Path $layout 'AppxManifest.xml'
[System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))

$makeAppx = Get-Command makeappx.exe -ErrorAction SilentlyContinue
if ($null -eq $makeAppx) {
    $sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $makeAppx = Get-ChildItem -LiteralPath $sdkRoot -Filter makeappx.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\makeappx\.exe$' } |
        Sort-Object FullName -Descending | Select-Object -First 1
}
if ($null -eq $makeAppx) { Stop-Hold 'MakeAppx.exe was not found in the Windows SDK' }

$packageName = "${Slug}_${version}_x64_QA_UNSIGNED.msix"
$packagePath = Join-Path $outRoot $packageName
Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
& $makeAppx.Source pack /o /v /d $layout /p $packagePath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { Stop-Hold 'MakeAppx failed to create MSIX' }

$hash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
$evidenceOut = [ordered]@{
    schema_version = '1.0'
    status = 'QA_UNSIGNED_MSIX'
    slug = $Slug
    source_sha = $currentHead
    identity_verified_source_sha = $verifiedSourceSha
    store_id = $storeId
    identity_name = $identityName
    publisher = $publisher
    version = $version
    verified_by = $verifiedBy
    evidence_url = $evidenceUrl
    msix_file = $packageName
    msix_sha256 = $hash
    signature_verified = $false
    windows_gpu_qa = 'NOT_RUN'
    store_submission = 'NOT_RUN'
}
$evidencePath = Join-Path $outRoot 'msix-evidence.json'
$evidenceOut | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $evidencePath -Encoding UTF8

# Publish a separate, strict two-file handoff for Windows-all-auto.
# The QA_UNSIGNED artifact is never a Store submission or certification claim.
$handoffRoot = Join-Path $outRoot 'handoff'
New-Item -ItemType Directory -Force -Path $handoffRoot | Out-Null
$handoffPackage = Join-Path $handoffRoot 'package.msix'
Copy-Item -LiteralPath $packagePath -Destination $handoffPackage -Force
$handoff = [ordered]@{
    schema_version = 1
    source_repository = 'https://github.com/shihuiarenjinba-png/3d-game-factory'
    source_sha = $currentHead
    type = '3d-game'
    slug = $Slug
    package = 'package.msix'
    status = 'QA_UNSIGNED'
    package_sha256 = $hash
    package_bytes = (Get-Item -LiteralPath $packagePath).Length
    identity = [ordered]@{
        name = $identityName
        publisher = $publisher
        version = $version
    }
}
$handoffPath = Join-Path $handoffRoot 'handoff.json'
$handoff | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $handoffPath -Encoding UTF8

Write-Host "Created unsigned Store candidate: $packagePath"
Write-Host "SHA256: $hash"
Write-Host 'HOLD remains until signature/Store validation and Windows GPU QA are completed.'
) { Stop-Hold 'invalid request_id' }
if ($productType -ne 'GAME_3D') { Stop-Hold 'approved identity product_type mismatch' }
if ($sourceFactory -ne '3d-game-factory') { Stop-Hold 'approved identity source_factory mismatch' }
if ($sourceRepository -ne 'shihuiarenjinba-png/3d-game-factory') { Stop-Hold 'approved identity source_repository mismatch' }
if ($sourceBranch -ne 'codex/3d-real-msix-build-path-20261027') { Stop-Hold 'approved identity source_branch mismatch' }
if ($identitySlug -ne $Slug) { Stop-Hold 'approved identity slug mismatch' }
if ($storeId -notmatch '^[A-Za-z0-9]{8,32}
if ($identityName -notmatch '^[A-Za-z][A-Za-z0-9._-]{2,49}$') { Stop-Hold 'invalid package Identity Name' }
if ($publisher -notmatch '^CN=') { Stop-Hold 'invalid Publisher subject' }
if ($version -notmatch '^\d{1,5}(\.\d{1,5}){3}$') { Stop-Hold 'invalid four-part package version' }
if ($verifiedSourceSha -notmatch '^[0-9a-f]{40}$') { Stop-Hold 'verified source SHA is missing or malformed' }
try { $evidence = [Uri]$evidenceUrl } catch { Stop-Hold 'invalid Partner Center evidence URL' }
if ($evidence.Scheme -ne 'https' -or $evidence.Host -notin @('partner.microsoft.com', 'partnercenter.microsoft.com')) {
    Stop-Hold 'untrusted Partner Center evidence URL'
}

$displayName = if ($identity.display_name) { [string]$identity.display_name } else { Require-Text $metadata 'display_name' 100 }
$publisherDisplayName = if ($identity.publisher_display_name) { [string]$identity.publisher_display_name } else { Require-Text $metadata 'publisher_display_name' 100 }
$description = Require-Text $metadata 'description' 200
$language = Require-Text $metadata 'language' 20
$minWindows = Require-Text $metadata 'min_windows_version' 32
$maxWindows = Require-Text $metadata 'max_windows_version_tested' 32
foreach ($osVersion in @($minWindows, $maxWindows)) {
    if ($osVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') { Stop-Hold 'Windows version metadata must use four-part notation' }
}

Push-Location $root
try {
    $currentHead = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentHead -notmatch '^[0-9a-f]{40}$') { Stop-Hold 'cannot resolve current Git HEAD' }
    $currentBranch = (& git symbolic-ref --quiet --short HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentBranch -ne 'codex/3d-real-msix-build-path-20261027') {
        Stop-Hold 'MSIX build requires the approved 3D Factory work branch'
    }
    # An unsigned package must never be built from a dirty/untracked product
    # while evidence incorrectly claims the clean commit HEAD as its source.
    $productChanges = @(& git status --porcelain --untracked-files=all -- ("products/" + $Slug))
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'cannot inspect product working tree' }
    if ($productChanges.Count -gt 0) {
        Stop-Hold 'product has uncommitted or untracked files; commit and review before MSIX build'
    }
    & git cat-file -e ($verifiedSourceSha + '^{commit}') 2>$null
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'verified source SHA is not present in checkout history' }
    $changed = @(& git diff --name-only ($verifiedSourceSha + '..HEAD') -- ("products/" + $Slug))
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'cannot compare product source to verified source SHA' }
    $allowedIdentityPath = "products/$Slug/store/approved-identity.json"
    $unexpected = @($changed | Where-Object { $_ -and $_ -ne $allowedIdentityPath })
    if ($unexpected.Count -gt 0) { Stop-Hold ("product changed after Identity verification: " + ($unexpected -join ', ')) }
}
finally { Pop-Location }

foreach ($asset in @('StoreLogo.png','Square150.png','Square44.png')) {
    $path = Join-Path $storeRoot $asset
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
        Stop-Hold "required Store asset is missing or empty: $asset"
    }
}

$godot = $env:GODOT_EXE
if ([string]::IsNullOrWhiteSpace($godot) -or -not (Test-Path -LiteralPath $godot -PathType Leaf)) { Stop-Hold 'GODOT_EXE is not configured' }

$outRoot = Join-Path $root $OutputDirectory
$godotOut = Join-Path $outRoot 'godot'
$layout = Join-Path $outRoot 'msix-layout'
Remove-Item -LiteralPath $godotOut -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $layout -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $godotOut, (Join-Path $layout 'Game'), (Join-Path $layout 'Assets') | Out-Null

$rawExe = Join-Path $godotOut 'game.exe'
& $godot --headless --path $productRoot --export-release 'Windows Desktop' $rawExe
if ($LASTEXITCODE -ne 0) { Stop-Hold 'Godot Windows export failed' }
if (-not (Test-Path -LiteralPath $rawExe -PathType Leaf) -or (Get-Item -LiteralPath $rawExe).Length -lt 1024) {
    Stop-Hold 'Godot export produced no usable executable'
}
$stream = [System.IO.File]::OpenRead($rawExe)
try {
    $b0 = $stream.ReadByte(); $b1 = $stream.ReadByte()
} finally { $stream.Dispose() }
if ($b0 -ne 0x4D -or $b1 -ne 0x5A) { Stop-Hold 'Godot export is not a Windows PE executable' }

Copy-Item -LiteralPath $rawExe -Destination (Join-Path $layout 'Game\game.exe')
$presetText = Get-Content -LiteralPath $presets -Raw -Encoding UTF8
if ($presetText -match '(?m)^\s*binary_format/embed_pck\s*=\s*false\s*$') {
    $rawPck = [System.IO.Path]::ChangeExtension($rawExe, '.pck')
    if (-not (Test-Path -LiteralPath $rawPck -PathType Leaf) -or (Get-Item -LiteralPath $rawPck).Length -eq 0) {
        Stop-Hold 'Godot export omitted required external PCK'
    }
    Copy-Item -LiteralPath $rawPck -Destination (Join-Path $layout 'Game\game.pck')
}

Copy-Item -LiteralPath (Join-Path $storeRoot 'StoreLogo.png') -Destination (Join-Path $layout 'Assets\StoreLogo.png')
Copy-Item -LiteralPath (Join-Path $storeRoot 'Square150.png') -Destination (Join-Path $layout 'Assets\Square150.png')
Copy-Item -LiteralPath (Join-Path $storeRoot 'Square44.png') -Destination (Join-Path $layout 'Assets\Square44.png')

$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:uap10="http://schemas.microsoft.com/appx/manifest/uap/windows10/10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  IgnorableNamespaces="uap uap10 rescap">
  <Identity Name="$(Xml-Escape $identityName)" Version="$(Xml-Escape $version)" Publisher="$(Xml-Escape $publisher)" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>$(Xml-Escape $displayName)</DisplayName>
    <PublisherDisplayName>$(Xml-Escape $publisherDisplayName)</PublisherDisplayName>
    <Description>$(Xml-Escape $description)</Description>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Resources>
    <Resource Language="$(Xml-Escape $language)" />
  </Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="$(Xml-Escape $minWindows)" MaxVersionTested="$(Xml-Escape $maxWindows)" />
  </Dependencies>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
  <Applications>
    <Application Id="Game" Executable="Game\game.exe" uap10:RuntimeBehavior="packagedClassicApp" uap10:TrustLevel="mediumIL">
      <uap:VisualElements DisplayName="$(Xml-Escape $displayName)" Description="$(Xml-Escape $description)" Square150x150Logo="Assets\Square150.png" Square44x44Logo="Assets\Square44.png" BackgroundColor="transparent" />
    </Application>
  </Applications>
</Package>
"@
$manifestPath = Join-Path $layout 'AppxManifest.xml'
[System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))

$makeAppx = Get-Command makeappx.exe -ErrorAction SilentlyContinue
if ($null -eq $makeAppx) {
    $sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $makeAppx = Get-ChildItem -LiteralPath $sdkRoot -Filter makeappx.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\makeappx\.exe$' } |
        Sort-Object FullName -Descending | Select-Object -First 1
}
if ($null -eq $makeAppx) { Stop-Hold 'MakeAppx.exe was not found in the Windows SDK' }

$packageName = "${Slug}_${version}_x64_QA_UNSIGNED.msix"
$packagePath = Join-Path $outRoot $packageName
Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
& $makeAppx.Source pack /o /v /d $layout /p $packagePath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { Stop-Hold 'MakeAppx failed to create MSIX' }

$hash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
$evidenceOut = [ordered]@{
    schema_version = '1.0'
    status = 'QA_UNSIGNED_MSIX'
    slug = $Slug
    source_sha = $currentHead
    identity_verified_source_sha = $verifiedSourceSha
    store_id = $storeId
    identity_name = $identityName
    publisher = $publisher
    version = $version
    verified_by = $verifiedBy
    evidence_url = $evidenceUrl
    msix_file = $packageName
    msix_sha256 = $hash
    signature_verified = $false
    windows_gpu_qa = 'NOT_RUN'
    store_submission = 'NOT_RUN'
}
$evidencePath = Join-Path $outRoot 'msix-evidence.json'
$evidenceOut | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $evidencePath -Encoding UTF8

# Publish a separate, strict two-file handoff for Windows-all-auto.
# The QA_UNSIGNED artifact is never a Store submission or certification claim.
$handoffRoot = Join-Path $outRoot 'handoff'
New-Item -ItemType Directory -Force -Path $handoffRoot | Out-Null
$handoffPackage = Join-Path $handoffRoot 'package.msix'
Copy-Item -LiteralPath $packagePath -Destination $handoffPackage -Force
$handoff = [ordered]@{
    schema_version = 1
    source_repository = 'https://github.com/shihuiarenjinba-png/3d-game-factory'
    source_sha = $currentHead
    type = '3d-game'
    slug = $Slug
    package = 'package.msix'
    status = 'QA_UNSIGNED'
    package_sha256 = $hash
    package_bytes = (Get-Item -LiteralPath $packagePath).Length
    identity = [ordered]@{
        name = $identityName
        publisher = $publisher
        version = $version
    }
}
$handoffPath = Join-Path $handoffRoot 'handoff.json'
$handoff | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $handoffPath -Encoding UTF8

Write-Host "Created unsigned Store candidate: $packagePath"
Write-Host "SHA256: $hash"
Write-Host 'HOLD remains until signature/Store validation and Windows GPU QA are completed.'
) { Stop-Hold 'invalid Store ID format' }
if ($identityName -notmatch '^[A-Za-z][A-Za-z0-9._-]{2,49}$') { Stop-Hold 'invalid package Identity Name' }
if ($publisher -notmatch '^CN=') { Stop-Hold 'invalid Publisher subject' }
if ($version -notmatch '^\d{1,5}(\.\d{1,5}){3}$') { Stop-Hold 'invalid four-part package version' }
if ($verifiedSourceSha -notmatch '^[0-9a-f]{40}$') { Stop-Hold 'verified source SHA is missing or malformed' }
try { $evidence = [Uri]$evidenceUrl } catch { Stop-Hold 'invalid Partner Center evidence URL' }
if ($evidence.Scheme -ne 'https' -or $evidence.Host -notin @('partner.microsoft.com', 'partnercenter.microsoft.com')) {
    Stop-Hold 'untrusted Partner Center evidence URL'
}

$displayName = if ($identity.display_name) { [string]$identity.display_name } else { Require-Text $metadata 'display_name' 100 }
$publisherDisplayName = if ($identity.publisher_display_name) { [string]$identity.publisher_display_name } else { Require-Text $metadata 'publisher_display_name' 100 }
$description = Require-Text $metadata 'description' 200
$language = Require-Text $metadata 'language' 20
$minWindows = Require-Text $metadata 'min_windows_version' 32
$maxWindows = Require-Text $metadata 'max_windows_version_tested' 32
foreach ($osVersion in @($minWindows, $maxWindows)) {
    if ($osVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') { Stop-Hold 'Windows version metadata must use four-part notation' }
}

Push-Location $root
try {
    $currentHead = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentHead -notmatch '^[0-9a-f]{40}$') { Stop-Hold 'cannot resolve current Git HEAD' }
    $currentBranch = (& git symbolic-ref --quiet --short HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentBranch -ne 'codex/3d-real-msix-build-path-20261027') {
        Stop-Hold 'MSIX build requires the approved 3D Factory work branch'
    }
    # An unsigned package must never be built from a dirty/untracked product
    # while evidence incorrectly claims the clean commit HEAD as its source.
    $productChanges = @(& git status --porcelain --untracked-files=all -- ("products/" + $Slug))
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'cannot inspect product working tree' }
    if ($productChanges.Count -gt 0) {
        Stop-Hold 'product has uncommitted or untracked files; commit and review before MSIX build'
    }
    & git cat-file -e ($verifiedSourceSha + '^{commit}') 2>$null
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'verified source SHA is not present in checkout history' }
    $changed = @(& git diff --name-only ($verifiedSourceSha + '..HEAD') -- ("products/" + $Slug))
    if ($LASTEXITCODE -ne 0) { Stop-Hold 'cannot compare product source to verified source SHA' }
    $allowedIdentityPath = "products/$Slug/store/approved-identity.json"
    $unexpected = @($changed | Where-Object { $_ -and $_ -ne $allowedIdentityPath })
    if ($unexpected.Count -gt 0) { Stop-Hold ("product changed after Identity verification: " + ($unexpected -join ', ')) }
}
finally { Pop-Location }

foreach ($asset in @('StoreLogo.png','Square150.png','Square44.png')) {
    $path = Join-Path $storeRoot $asset
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
        Stop-Hold "required Store asset is missing or empty: $asset"
    }
}

$godot = $env:GODOT_EXE
if ([string]::IsNullOrWhiteSpace($godot) -or -not (Test-Path -LiteralPath $godot -PathType Leaf)) { Stop-Hold 'GODOT_EXE is not configured' }

$outRoot = Join-Path $root $OutputDirectory
$godotOut = Join-Path $outRoot 'godot'
$layout = Join-Path $outRoot 'msix-layout'
Remove-Item -LiteralPath $godotOut -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $layout -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $godotOut, (Join-Path $layout 'Game'), (Join-Path $layout 'Assets') | Out-Null

$rawExe = Join-Path $godotOut 'game.exe'
& $godot --headless --path $productRoot --export-release 'Windows Desktop' $rawExe
if ($LASTEXITCODE -ne 0) { Stop-Hold 'Godot Windows export failed' }
if (-not (Test-Path -LiteralPath $rawExe -PathType Leaf) -or (Get-Item -LiteralPath $rawExe).Length -lt 1024) {
    Stop-Hold 'Godot export produced no usable executable'
}
$stream = [System.IO.File]::OpenRead($rawExe)
try {
    $b0 = $stream.ReadByte(); $b1 = $stream.ReadByte()
} finally { $stream.Dispose() }
if ($b0 -ne 0x4D -or $b1 -ne 0x5A) { Stop-Hold 'Godot export is not a Windows PE executable' }

Copy-Item -LiteralPath $rawExe -Destination (Join-Path $layout 'Game\game.exe')
$presetText = Get-Content -LiteralPath $presets -Raw -Encoding UTF8
if ($presetText -match '(?m)^\s*binary_format/embed_pck\s*=\s*false\s*$') {
    $rawPck = [System.IO.Path]::ChangeExtension($rawExe, '.pck')
    if (-not (Test-Path -LiteralPath $rawPck -PathType Leaf) -or (Get-Item -LiteralPath $rawPck).Length -eq 0) {
        Stop-Hold 'Godot export omitted required external PCK'
    }
    Copy-Item -LiteralPath $rawPck -Destination (Join-Path $layout 'Game\game.pck')
}

Copy-Item -LiteralPath (Join-Path $storeRoot 'StoreLogo.png') -Destination (Join-Path $layout 'Assets\StoreLogo.png')
Copy-Item -LiteralPath (Join-Path $storeRoot 'Square150.png') -Destination (Join-Path $layout 'Assets\Square150.png')
Copy-Item -LiteralPath (Join-Path $storeRoot 'Square44.png') -Destination (Join-Path $layout 'Assets\Square44.png')

$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:uap10="http://schemas.microsoft.com/appx/manifest/uap/windows10/10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  IgnorableNamespaces="uap uap10 rescap">
  <Identity Name="$(Xml-Escape $identityName)" Version="$(Xml-Escape $version)" Publisher="$(Xml-Escape $publisher)" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>$(Xml-Escape $displayName)</DisplayName>
    <PublisherDisplayName>$(Xml-Escape $publisherDisplayName)</PublisherDisplayName>
    <Description>$(Xml-Escape $description)</Description>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Resources>
    <Resource Language="$(Xml-Escape $language)" />
  </Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="$(Xml-Escape $minWindows)" MaxVersionTested="$(Xml-Escape $maxWindows)" />
  </Dependencies>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
  <Applications>
    <Application Id="Game" Executable="Game\game.exe" uap10:RuntimeBehavior="packagedClassicApp" uap10:TrustLevel="mediumIL">
      <uap:VisualElements DisplayName="$(Xml-Escape $displayName)" Description="$(Xml-Escape $description)" Square150x150Logo="Assets\Square150.png" Square44x44Logo="Assets\Square44.png" BackgroundColor="transparent" />
    </Application>
  </Applications>
</Package>
"@
$manifestPath = Join-Path $layout 'AppxManifest.xml'
[System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))

$makeAppx = Get-Command makeappx.exe -ErrorAction SilentlyContinue
if ($null -eq $makeAppx) {
    $sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $makeAppx = Get-ChildItem -LiteralPath $sdkRoot -Filter makeappx.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\makeappx\.exe$' } |
        Sort-Object FullName -Descending | Select-Object -First 1
}
if ($null -eq $makeAppx) { Stop-Hold 'MakeAppx.exe was not found in the Windows SDK' }

$packageName = "${Slug}_${version}_x64_QA_UNSIGNED.msix"
$packagePath = Join-Path $outRoot $packageName
Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
& $makeAppx.Source pack /o /v /d $layout /p $packagePath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { Stop-Hold 'MakeAppx failed to create MSIX' }

$hash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
$evidenceOut = [ordered]@{
    schema_version = '1.0'
    status = 'QA_UNSIGNED_MSIX'
    slug = $Slug
    source_sha = $currentHead
    identity_verified_source_sha = $verifiedSourceSha
    store_id = $storeId
    identity_name = $identityName
    publisher = $publisher
    version = $version
    verified_by = $verifiedBy
    evidence_url = $evidenceUrl
    msix_file = $packageName
    msix_sha256 = $hash
    signature_verified = $false
    windows_gpu_qa = 'NOT_RUN'
    store_submission = 'NOT_RUN'
}
$evidencePath = Join-Path $outRoot 'msix-evidence.json'
$evidenceOut | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $evidencePath -Encoding UTF8

# Publish a separate, strict two-file handoff for Windows-all-auto.
# The QA_UNSIGNED artifact is never a Store submission or certification claim.
$handoffRoot = Join-Path $outRoot 'handoff'
New-Item -ItemType Directory -Force -Path $handoffRoot | Out-Null
$handoffPackage = Join-Path $handoffRoot 'package.msix'
Copy-Item -LiteralPath $packagePath -Destination $handoffPackage -Force
$handoff = [ordered]@{
    schema_version = 1
    source_repository = 'https://github.com/shihuiarenjinba-png/3d-game-factory'
    source_sha = $currentHead
    type = '3d-game'
    slug = $Slug
    package = 'package.msix'
    status = 'QA_UNSIGNED'
    package_sha256 = $hash
    package_bytes = (Get-Item -LiteralPath $packagePath).Length
    identity = [ordered]@{
        name = $identityName
        publisher = $publisher
        version = $version
    }
}
$handoffPath = Join-Path $handoffRoot 'handoff.json'
$handoff | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $handoffPath -Encoding UTF8

Write-Host "Created unsigned Store candidate: $packagePath"
Write-Host "SHA256: $hash"
Write-Host 'HOLD remains until signature/Store validation and Windows GPU QA are completed.'
