/*
 * xiaomi_kbd_daemon - Bridge Xiaomi pogo-pin keyboard to Android input stack
 *
 * Reads raw input events from the physical keyboard device and forwards
 * them through a uinput virtual device so Android's InputReader can see them.
 *
 * Target: Xiaomi Pad 7 Pro, crDroid (AOSP), arm64-v8a
 * Keyboard: vendor=0x15d9, product=0x00a3 (German QWERTZ layout)
 */

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define UINPUT_DEVICE  "/dev/uinput"
#define INPUT_DIR      "/dev/input"

#define DEVICE_NAME    "Xiaomi Pogo Keyboard (Virtual)"
#define VENDOR_ID      0x15d9
#define PRODUCT_ID     0x00a3
#define VERSION_ID     1

#define RETRY_DELAY_SEC 3
#define LOG_TAG         "xiaomi_kbd"

/* Simple logging to Android's logcat via stderr (init redirects to kmsg) */
#define LOGI(fmt, ...) fprintf(stderr, LOG_TAG ": " fmt "\n", ##__VA_ARGS__)
#define LOGE(fmt, ...) fprintf(stderr, LOG_TAG " ERROR: " fmt "\n", ##__VA_ARGS__)

static volatile sig_atomic_t g_running = 1;

static void signal_handler(int sig) {
    (void)sig;
    g_running = 0;
}

/*
 * Scan /dev/input/event* for a device matching VENDOR_ID:PRODUCT_ID.
 * This handles dock/undock where the event node number can change.
 */
static int open_input_device(void) {
    DIR *dir = opendir(INPUT_DIR);
    if (!dir) {
        LOGE("opendir %s: %s", INPUT_DIR, strerror(errno));
        return -1;
    }

    struct dirent *ent;
    int fd = -1;

    while ((ent = readdir(dir)) != NULL) {
        if (strncmp(ent->d_name, "event", 5) != 0)
            continue;

        char path[128];
        snprintf(path, sizeof(path), "%s/%s", INPUT_DIR, ent->d_name);

        int tmpfd = open(path, O_RDONLY);
        if (tmpfd < 0)
            continue;

        struct input_id id;
        if (ioctl(tmpfd, EVIOCGID, &id) < 0) {
            close(tmpfd);
            continue;
        }

        if (id.vendor == VENDOR_ID && id.product == PRODUCT_ID) {
            LOGI("found keyboard at %s (vendor=0x%04x product=0x%04x)",
                 path, id.vendor, id.product);
            fd = tmpfd;
            break;
        }

        close(tmpfd);
    }

    closedir(dir);

    if (fd < 0) {
        LOGE("keyboard vendor=0x%04x product=0x%04x not found in %s",
             VENDOR_ID, PRODUCT_ID, INPUT_DIR);
        return -1;
    }

    /* Grab the device so the (broken) xiaomi_keyboard handler can't interfere */
    if (ioctl(fd, EVIOCGRAB, 1) < 0) {
        LOGE("EVIOCGRAB: %s (continuing without grab)", strerror(errno));
    }

    return fd;
}

static int setup_uinput(void) {
    int fd = open(UINPUT_DEVICE, O_WRONLY | O_NONBLOCK);
    if (fd < 0) {
        LOGE("open %s: %s", UINPUT_DEVICE, strerror(errno));
        return -1;
    }

    /* Enable EV_KEY */
    if (ioctl(fd, UI_SET_EVBIT, EV_KEY) < 0) {
        LOGE("UI_SET_EVBIT EV_KEY: %s", strerror(errno));
        goto fail;
    }

    /* Enable EV_REP for key repeat */
    if (ioctl(fd, UI_SET_EVBIT, EV_REP) < 0) {
        LOGE("UI_SET_EVBIT EV_REP: %s", strerror(errno));
        /* Non-fatal */
    }

    /* Enable EV_MSC for scan codes */
    if (ioctl(fd, UI_SET_EVBIT, EV_MSC) < 0) {
        LOGE("UI_SET_EVBIT EV_MSC: %s", strerror(errno));
    }
    ioctl(fd, UI_SET_MSCBIT, MSC_SCAN);

    /* Enable EV_SYN */
    if (ioctl(fd, UI_SET_EVBIT, EV_SYN) < 0) {
        LOGE("UI_SET_EVBIT EV_SYN: %s", strerror(errno));
    }

    /* Register all key codes (0..KEY_MAX) */
    for (int i = 0; i < KEY_MAX; i++) {
        ioctl(fd, UI_SET_KEYBIT, i);
    }

    /* Enable LED events (caps lock, num lock, etc.) */
    if (ioctl(fd, UI_SET_EVBIT, EV_LED) < 0) {
        LOGE("UI_SET_EVBIT EV_LED: %s", strerror(errno));
    }
    ioctl(fd, UI_SET_LEDBIT, LED_NUML);
    ioctl(fd, UI_SET_LEDBIT, LED_CAPSL);
    ioctl(fd, UI_SET_LEDBIT, LED_SCROLLL);

    /* Configure the virtual device */
    struct uinput_user_dev uidev;
    memset(&uidev, 0, sizeof(uidev));
    snprintf(uidev.name, UINPUT_MAX_NAME_SIZE, "%s", DEVICE_NAME);
    uidev.id.bustype = BUS_USB;
    uidev.id.vendor  = VENDOR_ID;
    uidev.id.product = PRODUCT_ID;
    uidev.id.version = VERSION_ID;

    if (write(fd, &uidev, sizeof(uidev)) != sizeof(uidev)) {
        LOGE("write uinput_user_dev: %s", strerror(errno));
        goto fail;
    }

    if (ioctl(fd, UI_DEV_CREATE) < 0) {
        LOGE("UI_DEV_CREATE: %s", strerror(errno));
        goto fail;
    }

    LOGI("uinput device created: %s", DEVICE_NAME);
    return fd;

fail:
    close(fd);
    return -1;
}

static void destroy_uinput(int fd) {
    if (fd >= 0) {
        ioctl(fd, UI_DEV_DESTROY);
        close(fd);
    }
}

static void event_loop(int input_fd, int uinput_fd) {
    struct input_event ev;

    LOGI("entering event loop");

    while (g_running) {
        ssize_t n = read(input_fd, &ev, sizeof(ev));
        if (n < 0) {
            if (errno == EINTR)
                continue;
            LOGE("read: %s", strerror(errno));
            break;
        }
        if (n != sizeof(ev)) {
            LOGE("short read: %zd bytes", n);
            break;
        }

        /* Forward the event as-is to the virtual device */
        ssize_t w = write(uinput_fd, &ev, sizeof(ev));
        if (w < 0) {
            if (errno == EINTR)
                continue;
            LOGE("write uinput: %s", strerror(errno));
            break;
        }
    }
}

static void daemonize(void) {
    pid_t pid = fork();
    if (pid < 0) {
        LOGE("fork: %s", strerror(errno));
        exit(1);
    }
    if (pid > 0) {
        /* Parent exits */
        exit(0);
    }

    /* Child becomes session leader */
    setsid();

    /* Redirect stdin to /dev/null */
    int devnull = open("/dev/null", O_RDWR);
    if (devnull >= 0) {
        dup2(devnull, STDIN_FILENO);
        /* Keep stderr for logging (goes to kmsg/logcat) */
        close(devnull);
    }
}

int main(int argc, char *argv[]) {
    int foreground = 0;

    if (argc > 1 && strcmp(argv[1], "-f") == 0)
        foreground = 1;

    /* Set up signal handlers for clean shutdown */
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = signal_handler;
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);

    /* Ignore SIGPIPE */
    sa.sa_handler = SIG_IGN;
    sigaction(SIGPIPE, &sa, NULL);

    if (!foreground)
        daemonize();

    LOGI("daemon starting (pid=%d)", getpid());

    /* Main retry loop - restart on errors */
    while (g_running) {
        int input_fd = open_input_device();
        if (input_fd < 0) {
            LOGE("retrying in %d seconds...", RETRY_DELAY_SEC);
            sleep(RETRY_DELAY_SEC);
            continue;
        }

        int uinput_fd = setup_uinput();
        if (uinput_fd < 0) {
            close(input_fd);
            LOGE("retrying in %d seconds...", RETRY_DELAY_SEC);
            sleep(RETRY_DELAY_SEC);
            continue;
        }

        event_loop(input_fd, uinput_fd);

        /* Cleanup before retry */
        destroy_uinput(uinput_fd);

        /* Release grab before closing */
        ioctl(input_fd, EVIOCGRAB, 0);
        close(input_fd);

        if (g_running) {
            LOGI("restarting in %d seconds...", RETRY_DELAY_SEC);
            sleep(RETRY_DELAY_SEC);
        }
    }

    LOGI("daemon exiting");
    return 0;
}
