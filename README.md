# Ferro

App de barra de menú para macOS que convierte el notch en una "isla" interactiva con animación de ferrofluido.

## Funciones

- **Música**: muestra lo que suena en Music o Spotify, controles de reproducción y letras.
- **Shelf**: arrastra archivos al notch para tenerlos a mano.
- **Portapapeles**: historial del portapapeles (ignora los elementos que los gestores de contraseñas marcan como ocultos).
- **Herramientas**: espejo con la cámara (solo mientras está abierto) y otras utilidades.
- Opción de abrir al iniciar sesión desde el icono de la barra de menú.

## Requisitos

- macOS 26 o superior
- Swift 6.2

## Compilar

```bash
./build.sh
```

Genera `build/Ferro.app` (firmada ad-hoc). Ábrela con doble clic o:

```bash
open build/Ferro.app
```
