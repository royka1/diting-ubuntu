/* Run a command with transparent huge pages disabled for it and all its
 * children (prctl PR_SET_THP_DISABLE is inherited across fork/exec).
 * Used to work around compiler crashes on the build host; see
 * ubuntu-diting/docs/BUILD.md. */
#include <stdio.h>
#include <sys/prctl.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	if (argc < 2) {
		fprintf(stderr, "usage: nothp command [args...]\n");
		return 2;
	}
	if (prctl(PR_SET_THP_DISABLE, 1, 0, 0, 0)) {
		perror("prctl(PR_SET_THP_DISABLE)");
		return 1;
	}
	execvp(argv[1], argv + 1);
	perror(argv[1]);
	return 127;
}
