#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern char** environ;

#ifndef ENTRYPOINT
#define ENTRYPOINT "/usr/local/bin/entrypoint.sh"
#endif

int main(int argc, char *argv[])
{
    char **newargv = (char**) malloc ( (argc+2) * sizeof(char*) );
    if (argc > 1)
    {
        memcpy(&newargv[1], &argv[1], (argc) * sizeof(char*));
    }
    newargv[0] = ENTRYPOINT;
    newargv[argc+1] = NULL;

    printf("%s: info: EUID=%d\n", argv[0], geteuid());

    if (setuid( 0 ) != 0)
    {
        fprintf(stderr, "%s: error: setuid(0) failed\n", argv[0]);
        exit(EXIT_FAILURE);
    }
    execve(ENTRYPOINT, newargv, environ);
    perror(ENTRYPOINT);   /* execve() returns only on error */
    exit(EXIT_FAILURE);
}
