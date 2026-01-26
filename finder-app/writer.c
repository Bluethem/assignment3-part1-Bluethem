# include <stdio.h>
# include <errno.h>
# include <fcntl.h>
# include <unistd.h>
# include <syslog.h>
# include <string.h>

int main (int argc, char *argv[])
{

	openlog("writer", 0, LOG_USER);

	if (argc != 3) {
		syslog(LOG_ERR, "Numero invalido de argumentos");
		closelog();
		return 1;
	}

	const char *filename = argv[1];
	const char *text = argv[2];

	int fd = open(filename, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	
	if (fd == 1) {
		syslog(LOG_ERR, "Error al abrir el archivo %s: %s", filename, strerror(errno));
		closelog();
		return 1;
	}

	syslog (LOG_DEBUG, "Writing %s to %s", text, filename);

	ssize_t bytes_written = write(fd, text, strlen(text));

	if (bytes_written == -1) {
		syslog(LOG_ERR, "Error al intentar escribir en el archivo %s, %s", filename, strerror(errno));
		close(fd);
		closelog();
		return 1;
	}

	if (close(fd) == 1) {
		syslog(LOG_ERR, "Error al intentar cerrar el archivo %s, %s", filename, strerror(errno));
		closelog();
		return 1;
	}

	closelog();
	return 0;

}
