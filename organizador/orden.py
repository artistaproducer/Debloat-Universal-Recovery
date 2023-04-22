import os

# Obtener la ruta del directorio actual
ruta = os.path.dirname(os.path.abspath(__file__))

# Recorrer todos los archivos en el directorio
for nombre_archivo in os.listdir(ruta):
    # Verificar que el archivo es un archivo de texto
    if nombre_archivo.endswith('.sh'):
        # Leer el archivo
        with open(os.path.join(ruta, nombre_archivo), 'r') as archivo:
            lineas = archivo.readlines()
        # Eliminar líneas repetidas y ordenar alfabéticamente
        lineas_ordenadas = sorted(set(lineas))
        # Sobrescribir el archivo original con las líneas ordenadas y sin repeticiones
        with open(os.path.join(ruta, nombre_archivo), 'w') as archivo:
            archivo.writelines(lineas_ordenadas)