#include <X11/Xlib.h>
#include <assert.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/signalfd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define PERROR(msg)     \
  do {                  \
    perror(msg);        \
    exit(EXIT_FAILURE); \
  } while (0)

int main(void) {
  // Open a connection to the X server.
  Display* dpy = XOpenDisplay(NULL);
  if (!dpy)
    PERROR("XOpenDisplay");

  // Select for CreateNotify events on the root window before the program runs.
  Window root = DefaultRootWindow(dpy);
  XSelectInput(dpy, root, SubstructureNotifyMask);
  XFlush(dpy);

  // Redirect SIGCHLD to a signalfd.
  sigset_t mask;
  sigemptyset(&mask);
  sigaddset(&mask, SIGCHLD);
  if (sigprocmask(SIG_BLOCK, &mask, NULL) == -1)
    PERROR("sigprocmask");
  int sfd = signalfd(-1, &mask, 0);
  if (sfd == -1)
    PERROR("signalfd");

  // Run xfswm-init.
  pid_t pid = fork();
  if (pid < 0)
    PERROR("fork");
  if (pid == 0) {
    char* const argv[] = {NULL};
    execv("/usr/lib/xfswm-init", argv);
    PERROR("execv");
  }

  int xfd = ConnectionNumber(dpy);
  Window window = None;
  while (1) {
    // Wait for sfd or xfd to become readable.
    fd_set in_fds;
    FD_ZERO(&in_fds);
    FD_SET(xfd, &in_fds);
    FD_SET(sfd, &in_fds);
    int max_fd = sfd > xfd ? sfd : xfd;
    int ret = select(max_fd + 1, &in_fds, NULL, NULL, NULL);
    if (ret == -1 && errno != EINTR)
      PERROR("select");
    if (ret <= 0)
      continue;

    // Check if an X event is available.
    if (FD_ISSET(xfd, &in_fds) && XEventsQueued(dpy, QueuedAfterReading)) {
      XEvent event;
      XNextEvent(dpy, &event);

      // Check for the first window creation.
      if (event.type == CreateNotify && window == None) {
        window = event.xcreatewindow.window;
        XSelectInput(dpy, root, StructureNotifyMask);

        Window root_ret;
        int x, y;
        unsigned int width, height, border, depth;
        if (XGetGeometry(dpy, root, &root_ret, &x, &y, &width, &height, &border,
                         &depth)) {
          XMoveResizeWindow(dpy, window, 0, 0, width, height);
        }
      }

      // Check for a root window resize.
      if (event.type == ConfigureNotify && event.xconfigure.window == root) {
        assert(window != None);
        XMoveResizeWindow(dpy, window, 0, 0, event.xconfigure.width,
                          event.xconfigure.height);
      }

      XFlush(dpy);
    }

    // Check if a child has exited.
    if (FD_ISSET(sfd, &in_fds)) {
      struct signalfd_siginfo fdsi;
      ssize_t s = read(sfd, &fdsi, sizeof(fdsi));
      if (s != sizeof(fdsi))
        PERROR("read");
      pid_t waited = waitpid(-1, NULL, WNOHANG);
      if (waited == -1)
        PERROR("waitpid");
      if (waited == pid)
        break;
    }
  }

  XCloseDisplay(dpy);
  return EXIT_SUCCESS;
}
