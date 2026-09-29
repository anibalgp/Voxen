# Voxen

Voxen es un asistente de conversación por voz en tiempo real, diseñado para ofrecer una experiencia fluida, rápida y privada. Permite practicar conversación en otros idiomas o interactuar con modelos de inteligencia artificial directamente desde tu terminal, con soporte tanto para modelos locales offline como para conexiones rápidas a servicios en la nube.

---

## Características Principales

- **Conversación por Voz Fluida:** Habla con el asistente y escucha sus respuestas de forma natural y con baja latencia.
- **Privacidad Total o Modo Ligero:**
  - **Modo Local (100% Offline):** Todo el procesamiento se realiza en tu equipo, sin enviar audio ni texto a servidores externos.
  - **Modo Nube (Mínimo consumo de recursos):** Conexión con proveedores externos compatibles (como Groq, OpenRouter o Cohere) para funcionar en equipos con poca memoria RAM.
- **Tecnologías Integradas:**
  - **Reconocimiento de voz (STT):** Transcripción precisa impulsada por tecnología Whisper.
  - **Síntesis de voz (TTS):** Generación de voz clara y natural mediante Piper.
  - **Modelos de lenguaje (LLM):** Inferencia local optimizada o conexión a APIs remotas.
- **Multiplataforma:** Compatible con Linux, macOS y Windows.

---

## Instalación

Elige tu sistema operativo y sigue los pasos para instalar y configurar Voxen:

### Linux

Abre tu terminal y ejecuta:

```bash
curl -fL https://raw.githubusercontent.com/anibalgp/Voxen/main/voxen.sh -o voxen.sh
chmod +x voxen.sh
./voxen.sh
```

El instalador detectará las características de tu equipo y te guiará para seleccionar los modelos de voz y razonamiento más adecuados.

---

### macOS

Compatible con procesadores Apple Silicon (M1, M2, M3, M4) y procesadores Intel:

```bash
curl -fL https://raw.githubusercontent.com/anibalgp/Voxen/main/voxen.sh -o voxen.sh
chmod +x voxen.sh
./voxen.sh
```

> **Nota para usuarios de macOS:** La primera vez que inicies Voxen, el sistema operativo puede solicitar acceso al micrófono para la aplicación de terminal. Concede el permiso en: *Ajustes del Sistema > Privacidad y Seguridad > Micrófono*.

---

### Windows 10 / 11

En Windows, la forma recomendada es utilizar **Git Bash** (incluido al instalar [Git para Windows](https://git-scm.com/download/win)):

1. Abre la aplicación **Git Bash**.
2. Ejecuta el comando de instalación:
   ```bash
   curl -fL https://raw.githubusercontent.com/anibalgp/Voxen/main/voxen.sh -o voxen.sh
   chmod +x voxen.sh
   ./voxen.sh
   ```
3. El instalador descargará automáticamente los paquetes y componentes preparados para el entorno de Windows.

*(Si utilizas **WSL2** en Windows, puedes seguir directamente los pasos de la sección Linux).*

---

### Descarga Manual (GitHub Releases)

Si prefieres descargar el paquete precompilado directamente sin utilizar el script en línea:

1. Ingresa a la sección de **[Releases](https://github.com/anibalgp/Voxen/releases)** de este repositorio.
2. Descarga el archivo comprimido correspondiente a tu sistema:
   - **Linux:** `voxen-linux-x86_64.tar.gz`
   - **Windows:** `voxen-windows-x86_64.zip`
   - **macOS:** `voxen-macos-arm64.tar.gz`
3. Descomprime el archivo y ejecuta el asistente `./voxen.sh` incluido para inicializar tu configuración.

---

## Modo de Uso

Una vez completada la instalación, inicia el asistente ejecutando:

```bash
./voxen
```

Para forzar el uso del proveedor en la nube configurado:

```bash
./voxen --remote
```

### Controles durante la sesión:
- **Para hablar:** Presiona y mantén la tecla asignada o la barra espaciadora según la indicación en pantalla.
- **Para salir:** Presiona `Ctrl + C` en la terminal.

---

## Requisitos de Hardware

| Modo de Operación | Memoria RAM Recomendada | Conexión a Internet |
| :--- | :--- | :--- |
| **Nube (Groq / OpenRouter / Cohere)** | 2 GB a 4 GB RAM | Requerida durante la sesión |
| **Local Offline (Whisper Base + Modelo 1B-3B)** | 6 GB a 8 GB RAM | Solo requerida para la descarga inicial |
| **Local Offline Ligero (Whisper Tiny + Modelo 0.5B)** | 4 GB RAM | Solo requerida para la descarga inicial |

---

## Preguntas Frecuentes y Solución de Problemas

### El micrófono no es detectado en Linux
Verifica que tu servidor de audio (PipeWire o PulseAudio) esté activo y que tu usuario tenga permisos sobre los dispositivos de grabación:
```bash
arecord -l
```
Si el hardware aparece en la lista, comprueba que el volumen de captura no esté silenciado en los ajustes de sonido del sistema.

### Modificar la configuración después de la instalación
Puedes volver a ejecutar `./voxen.sh` en cualquier momento para seleccionar otros modelos o cambiar de modo. También puedes editar directamente las variables guardadas en el archivo `.env`.

### Dónde se almacenan los datos
Toda la configuración y preferencias se almacenan localmente en el archivo `.env` dentro del directorio donde se ejecuta Voxen. Ninguna información personal se almacena en servidores externos.

---

## Licencia y Términos

Voxen se distribuye para uso personal. Para más detalles sobre distribución y soporte, consulta la información oficial en este repositorio.
