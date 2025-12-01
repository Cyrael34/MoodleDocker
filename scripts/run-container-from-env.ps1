# /C:/Users/profe/OneDrive/2025-2026/TemplateDockerapp/scripts/run-container-from-env.ps1

# Cargar variables de entorno desde el archivo
$envFile = ".\env\dev.env"
$envVars = @{}

if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^=]+)=(.*)$') {
            $envVars[$matches[1]] = $matches[2]
        }
    }
}
else {
    Write-Error "Archivo $envFile no encontrado"
    exit 1
}

# Configurar variables
$containerName = $envVars['CONTAINER_NAME'] ?? 'ApachePHPContainer'
$portMapping = $envVars['PORT_MAPPING'] ?? '8081:80'
$volumePath = $envVars['VOLUME_PATH'] ?? '.\src'
$imageName = $envVars['IMAGE_NAME'] ?? 'apachephp:dev'
$hostEntry = $envVars['HOST_ENTRY'] ?? 'moodle.asir:127.0.0.1'

# Construir y ejecutar comando docker
$dockerCmd = @(
    "docker run -d",
    "--name $containerName",
    "-p $portMapping",
    "-v ${volumePath}:/var/www/moodle.asir",
    "--env-file $envFile",
    "--add-host=$hostEntry",
    "--hostname $containerName",
    $imageName
) -join ' '

Write-Host "Ejecutando: $dockerCmd"
Invoke-Expression $dockerCmd