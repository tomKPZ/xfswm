#include <X11/Xlib.h>
#include <errno.h>
#include <stdio.h>
#include <unistd.h>

int main(void) {
  Display* dpy = XOpenDisplay(NULL);
  if (!dpy)
    return 1;

  Window root = DefaultRootWindow(dpy);
  XSelectInput(dpy, root, SubstructureNotifyMask);

  Screen* screen = DefaultScreenOfDisplay(dpy);
  int fd = ConnectionNumber(dpy);

  pid_t pid = fork();
  if (pid < 0) {
    perror("fork");
    return 1;
  }
  if (pid == 0) {
    char* const argv[] = {NULL};
    execv("/usr/lib/xfswm-init", argv);
    perror("execv");
    return 1;
  }

  while (1) {
    XFlush(dpy);

    fd_set in_fds;
    FD_ZERO(&in_fds);
    FD_SET(fd, &in_fds);
    int ret = select(fd + 1, &in_fds, NULL, NULL, NULL);
    if (ret == -1) {
      if (errno != EINTR) {
        perror("select");
        goto cleanup;
      }
    } else if (ret > 0) {
      if (XPending(dpy)) {
        XEvent event;
        XNextEvent(dpy, &event);
        if (event.type == CreateNotify) {
          Window window = event.xcreatewindow.window;
          XMoveResizeWindow(dpy, window, 0, 0, WidthOfScreen(screen),
                            HeightOfScreen(screen));
        }
      }
    }
  }

cleanup:
  XCloseDisplay(dpy);
  return 0;
}
