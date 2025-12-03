# Define parameters with default values
param(
    [string]$envFile = ".\env\dev.mysql.env"
)
$envVars = @{}

if (-not (Test-Path $envFile)) {
    Write-Error "Env file '$envFile' not found."
    exit 1
} 
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([^=]+)=(.*)$') {
        $envVars[$matches[1]] = $matches[2]
    }
}
$Dockerfile = $envVars['DB_DOCKERFILE']
$Tag = $envVars['DB_IMAGE_NAME']
$buildArgsSTR = @(
    "--build-arg DB_USER=" + $envVars['DB_USER'],
    "--build-arg DB_PASS=" + $envVars['DB_PASS'],
    "--build-arg DB_ROOT_PASS=" + $envVars['DB_ROOT_PASS'],
    "--build-arg DB_DATADIR=" + $envVars['DB_DATADIR'],
    "--build-arg DB_PORT=" + $envVars['DB_PORT']
) -join ' '

$argsSTR = @('build', '--no-cache', '-f', $Dockerfile, '-t', $Tag, $buildArgsSTR, '.') -join ' '

Write-Host "Ejecutando: docker $argsSTR" 
docker @argsSTR
$code = $LASTEXITCODE
if ($code -ne 0) {
    Write-Error "docker build falló con código $code"
    exit $code
}