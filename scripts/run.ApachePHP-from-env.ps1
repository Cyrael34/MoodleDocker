Param(
    [string]$envFile = ".\env\dev.apachephp.env"
)
# Cargar variables de entorno desde el archivo
$envVars = @{}

if (-not (Test-Path $envFile)) {
    Write-Error "Archivo de entorno '$envFile' no encontrado."
    exit 1
}


Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([^=]+)=(.*)$') {
        $envVars[$matches[1]] = $matches[2]
    }
}

# Configurar variables
$imageName = $envVars['IMAGE_NAME']
$containerName = $envVars['CONTAINER_NAME'] 
$ip = $envVars['SERVER_IP']

$moodleservername = $envVars['MOODLE_SERVER_NAME']
$servername = $envVars['SERVER_NAME']
$moodleserverport = $envVars['MOODLE_SERVER_PORT']

$MOODLE_VOLUME_PATH = $envVars['MOODLE_VOLUME_PATH']
$volumePath = $envVars['VOLUME_PATH']
$networkName = $envVars['NETWORK_NAME']

if (
        $envVars['NETWORK_NAME'] -and `
        $envVars['NETWORK_SUBNET'] -and `
        $envVars['NETWORK_SUBNET_GATEWAY'] -and `
        $envVars['IP'] -and `
        -not (docker network ls --filter "name=^${envVars['NETWORK_NAME]}$" --format "{{.Name}}")
    ) {
        $networkName = $envVars['NETWORK_NAME']
        
        Write-Host "Creando red: $networkName"
        docker network create $networkName --subnet=$($envVars['NETWORK_SUBNET']) --gateway=$($envVars['NETWORK_SUBNET_GATEWAY'])
    }


# Eliminar contenedor si existe
if (docker ps -a --filter "name=^${containerName}$" --format "{{.Names}}" | Select-Object -First 1) {
    Write-Host "Eliminando contenedor existente: $containerName"
    docker stop $containerName 2>$null
    docker rm $containerName 2>$null
}

# Ejecutar el contenedor Docker
$dockerCmd = @(
    "docker run -d",
    "--name ${containerName}",
    "-p ${moodleserverport}:80",
    "-v ${volumePath}:/var/www/localhost/htdocs",
    "-v ${MOODLE_VOLUME_PATH}:/var/www/${moodleservername}",
    "-v .\logs\apachephp:/var/log/apache2",
    "--env-file $envFile",
    "--hostname $containerName",
    "--network $networkName",
    "--ip $ip",
    "--add-host ${servername}:${ip}",
    "--add-host ${moodleservername}:${ip}",
    $imageName
) -join ' '

Write-Host "Ejecutando: $dockerCmd"
Invoke-Expression $dockerCmd