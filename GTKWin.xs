#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <gtk/gtk.h>
#include <pcap.h>

#ifdef __linux__
#include <pcap/sll.h>
#endif

#include <stdio.h>
#include <string.h>
#include <arpa/inet.h>
#include <netinet/ip.h>
#include <netinet/udp.h>
#include <net/ethernet.h>

typedef struct {
    SV *from;
    SV *to;
} BindingUserdata;

gboolean
perl_timeout_func(gpointer userdata) {
    SV *callback = (SV *)userdata;
    if (!SvOK(callback)) {
        return FALSE;
    }

    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);

    PUTBACK;

    int count = call_sv(callback, G_SCALAR | G_EVAL);
    bool out = false;

    SPAGAIN;

    if (SvTRUE(ERRSV)) {
        Perl_warn("Perl binding callback failed: %s",
             SvPV_nolen(ERRSV));

        sv_setsv(ERRSV, &PL_sv_undef);
        count = 0;
    }

    if (count >= 1) {
        SV *ret = POPs;

        out = SvTRUE(ret);
    }

    PUTBACK;

    FREETMPS;
    LEAVE;

    return out;
}

static gboolean
sv_to_gvalue(SV *sv, GValue *value)
{
    if (G_VALUE_HOLDS_BOOLEAN(value)) {
        g_value_set_boolean(value, SvTRUE(sv));
        return TRUE;
    }

    if (G_VALUE_HOLDS_CHAR(value)) {
        g_value_set_schar(value, (gchar)SvIV(sv));
        return TRUE;
    }

    if (G_VALUE_HOLDS_UCHAR(value)) {
        g_value_set_uchar(value, (guchar)SvUV(sv));
        return TRUE;
    }

    if (G_VALUE_HOLDS_INT(value)) {
        g_value_set_int(value, (gint)SvIV(sv));
        return TRUE;
    }

    if (G_VALUE_HOLDS_UINT(value)) {
        g_value_set_uint(value, (guint)SvUV(sv));
        return TRUE;
    }

    if (G_VALUE_HOLDS_LONG(value)) {
        g_value_set_long(value, (glong)SvIV(sv));
        return TRUE;
    }

    if (G_VALUE_HOLDS_ULONG(value)) {
        g_value_set_ulong(value, (gulong)SvUV(sv));
        return TRUE;
    }

    if (G_VALUE_HOLDS_INT64(value)) {
        g_value_set_int64(value, (gint64)SvIV(sv));
        return TRUE;
    }

    if (G_VALUE_HOLDS_UINT64(value)) {
        g_value_set_uint64(value, (guint64)SvUV(sv));
        return TRUE;
    }

    if (G_VALUE_HOLDS_FLOAT(value)) {
        g_value_set_float(value, (gfloat)SvNV(sv));
        return TRUE;
    }

    if (G_VALUE_HOLDS_DOUBLE(value)) {
        g_value_set_double(value, SvNV(sv));
        return TRUE;
    }

    if (G_VALUE_HOLDS_STRING(value)) {
        if (SvOK(sv)) {
            STRLEN len;
            const gchar *str = SvPVutf8(sv, len);
            g_value_set_string(value, str);
        } else {
            g_value_set_string(value, NULL);
        }

        return TRUE;
    }

    if (G_VALUE_HOLDS_ENUM(value)) {
        g_value_set_enum(value, (gint)SvIV(sv));
        return TRUE;
    }

    if (G_VALUE_HOLDS_FLAGS(value)) {
        g_value_set_flags(value, (guint)SvUV(sv));
        return TRUE;
    }

    if (G_VALUE_HOLDS_GTYPE(value)) {
        g_value_set_gtype(value, (GType)SvUV(sv));
        return TRUE;
    }

    if (G_VALUE_HOLDS_OBJECT(value)) {
        if (!SvOK(sv)) {
            g_value_set_object(value, NULL);
            return TRUE;
        }

        if (!sv_isobject(sv))
            croak("Expected G::Object object");

        IV iv = SvIV(SvRV(sv));
        GObject *obj = INT2PTR(GObject *, iv);

        if (!G_IS_OBJECT(obj))
            croak("Invalid GObject pointer");

        if (!G_TYPE_CHECK_INSTANCE_TYPE(obj, G_VALUE_TYPE(value)))
            croak("Expected object of type %s",
                  g_type_name(G_VALUE_TYPE(value)));

        g_value_set_object(value, obj);
        return TRUE;
    }

    croak("Unsupported GValue type '%s'",
          g_type_name(G_VALUE_TYPE(value)));

    return FALSE;
}

static SV *
gvalue_to_sv(const GValue *value)
{
    if (G_VALUE_HOLDS_BOOLEAN(value))
        return newSViv(g_value_get_boolean(value));

    if (G_VALUE_HOLDS_CHAR(value))
        return newSViv(g_value_get_schar(value));

    if (G_VALUE_HOLDS_UCHAR(value))
        return newSVuv(g_value_get_uchar(value));

    if (G_VALUE_HOLDS_INT(value))
        return newSViv(g_value_get_int(value));

    if (G_VALUE_HOLDS_UINT(value))
        return newSVuv(g_value_get_uint(value));

    if (G_VALUE_HOLDS_LONG(value))
        return newSViv(g_value_get_long(value));

    if (G_VALUE_HOLDS_ULONG(value))
        return newSVuv(g_value_get_ulong(value));

    if (G_VALUE_HOLDS_INT64(value))
        return newSViv(g_value_get_int64(value));

    if (G_VALUE_HOLDS_UINT64(value))
        return newSVuv(g_value_get_uint64(value));

    if (G_VALUE_HOLDS_FLOAT(value))
        return newSVnv(g_value_get_float(value));

    if (G_VALUE_HOLDS_DOUBLE(value))
        return newSVnv(g_value_get_double(value));

    if (G_VALUE_HOLDS_STRING(value)) {
        const gchar *s = g_value_get_string(value);

        if (!s)
            return newSV(0);

        SV *sv = newSVpv(s, 0);
        SvUTF8_on(sv);
        return sv;
    }

    if (G_VALUE_HOLDS_ENUM(value))
        return newSViv(g_value_get_enum(value));

    if (G_VALUE_HOLDS_FLAGS(value))
        return newSVuv(g_value_get_flags(value));

    if (G_VALUE_HOLDS_GTYPE(value))
        return newSVuv(g_value_get_gtype(value));

    if (G_VALUE_HOLDS_OBJECT(value)) {
        GObject *obj = g_value_get_object(value);

        if (!obj)
            return newSV(0);

        SV *sv = newSV(0);
        sv_setref_pv(sv, "G::Object", obj);

        return sv;
    }

    croak("Unsupported GValue type '%s'",
          g_type_name(G_VALUE_TYPE(value)));
}

typedef struct {
    SV *callback;
    int datalink;
} PCAPContext;

typedef struct
{
    char src_ip[INET_ADDRSTRLEN];
    char dst_ip[INET_ADDRSTRLEN];

    unsigned short src_port;
    unsigned short dst_port;

    unsigned char src_mac[6];
    unsigned char dst_mac[6];

    const unsigned char *payload;
    int payload_len;

} UDPPacketInfo;

#include "typedefs.h"

static int
parse_udp_packet(const unsigned char *packet,
                 int datalink,
                 int packet_len,
                 UDPPacketInfo *info)
{
    const struct ether_header *eth;
    const struct ip *ip;
    const struct udphdr *udp;

    int offset = 0;


    if (packet_len < sizeof(struct ether_header))
        return 0;


    switch (datalink) {

    case DLT_RAW:
        offset = 0;
        break;

    case DLT_NULL:
    case DLT_LOOP:
        offset = sizeof(uint32_t);
        break;

    case DLT_EN10MB:
        offset = sizeof(struct ether_header);
        break;

    #ifdef DLT_LINUX_SLL
    case DLT_LINUX_SLL:
        offset = sizeof(struct sll_header);
        break;
    #endif

    default:
        return 0;
    }

    if (packet_len < offset) {
        return 0;
    }

    ip = (const struct ip *)(packet + offset);


    if (ip->ip_p != IPPROTO_UDP)
        return 0;


    inet_ntop(AF_INET,
              &ip->ip_src,
              info->src_ip,
              sizeof(info->src_ip));

    inet_ntop(AF_INET,
              &ip->ip_dst,
              info->dst_ip,
              sizeof(info->dst_ip));


    offset += ip->ip_hl * 4;


    if (packet_len < offset + sizeof(struct udphdr))
        return 0;


    udp = (const struct udphdr *)(packet + offset);


    info->src_port = ntohs(udp->uh_sport);
    info->dst_port = ntohs(udp->uh_dport);


    offset += sizeof(struct udphdr);


    info->payload = packet + offset;

    info->payload_len =
        packet_len - offset;


    return 1;
}

static void
gtk_win_pcap_handler(u_char *userdata,
             const struct pcap_pkthdr *header,
             const u_char *packet)
{
    PCAPContext *ctx = (PCAPContext *)userdata;
    SV *callback = ctx->callback;
    int datalink = ctx->datalink;
    dSP;

    UDPPacketInfo *udp_packet_info;

    Newxz(udp_packet_info, 1, UDPPacketInfo);

    parse_udp_packet(packet, datalink, header->caplen, udp_packet_info);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);

    XPUSHs(sv_2mortal(
        sv_setref_pv(newSV(0),
                     "PCAP::Packet",
                     (void *)udp_packet_info)
    ));

    PUTBACK;

    SvREFCNT_inc(callback);
    call_sv(callback, G_DISCARD);

    FREETMPS;
    LEAVE;
}

static gboolean
binding_callback(GBinding     *binding,
                      const GValue *from_value,
                      GValue       *to_value,
                      SV *callback)
{
    if (!SvOK(callback)) {
        return FALSE;
    }
    gboolean handled = FALSE;

    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);

    XPUSHs(sv_2mortal(gvalue_to_sv(from_value)));

    PUTBACK;

    int count = call_sv(callback, G_SCALAR | G_EVAL);

    SPAGAIN;

    if (SvTRUE(ERRSV)) {
        Perl_warn("Perl binding callback failed: %s",
             SvPV_nolen(ERRSV));

        sv_setsv(ERRSV, &PL_sv_undef);
        count = 0;
    }

    if (count >= 1) {
        SV *ret = POPs;

        handled = sv_to_gvalue(ret, to_value);
    }

    PUTBACK;

    FREETMPS;
    LEAVE;

    return handled;
}

static gboolean
binding_callback_from(GBinding *binding,
    const GValue *from_value,
    GValue *to_value,
    gpointer user_data) {
    BindingUserdata *binding_data = (BindingUserdata *) user_data;
    SV *callback = binding_data->from;
    return binding_callback(binding, from_value, to_value, callback);
}
static gboolean
binding_callback_to(GBinding *binding,
    const GValue *from_value,
    GValue *to_value,
    gpointer user_data) {
    BindingUserdata *binding_data = (BindingUserdata *) user_data;
    SV *callback = binding_data->to;
    return binding_callback(binding, from_value, to_value, callback);
}

static void
perl_signal_callback(GObject *object, gpointer data)
{
    SV *callback = (SV *)data;
    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);

    XPUSHs(sv_2mortal(newSViv(PTR2IV(object))));
    PUTBACK;

    call_sv(callback, G_DISCARD | G_EVAL);

    SPAGAIN;

    if (SvTRUE(ERRSV)) {
        Perl_warn("Unhandled GObject connect callback error: %s",
                  SvPV_nolen(ERRSV));

        sv_setsv(ERRSV, &PL_sv_undef);
    }

    PUTBACK;

    FREETMPS;
    LEAVE;
}

MODULE = GTKWin PACKAGE = Front::Net::IfIp

char *
to_reach(SV *class, const char *dest)
    CODE:
        struct addrinfo hints = {0};
        struct addrinfo *res = NULL;
        int sock = -1;
        int rc;

        hints.ai_family = AF_INET;          /* IPv4 only */
        hints.ai_socktype = SOCK_DGRAM;
        hints.ai_protocol = IPPROTO_UDP;

        rc = getaddrinfo(dest, "53", &hints, &res);
        if (rc != 0) {
            Perl_croak("getaddrinfo(%s): %s",
                       dest, gai_strerror(rc));
        }

        sock = socket(res->ai_family,
                      res->ai_socktype,
                      res->ai_protocol);
        if (sock < 0) {
            int err = errno;
            freeaddrinfo(res);
            Perl_croak("socket failed: errno=%d (%s)",
                       err, strerror(err));
        }

        if (connect(sock, res->ai_addr, res->ai_addrlen) < 0) {
            int err = errno;
            freeaddrinfo(res);
            close(sock);
            Perl_croak("connect failed: errno=%d (%s)",
                       err, strerror(err));
        }

        freeaddrinfo(res);

        struct sockaddr_in local;
        socklen_t len = sizeof(local);

        if (getsockname(sock, (struct sockaddr *)&local, &len) < 0) {
            int err = errno;
            close(sock);
            Perl_croak("getsockname failed: errno=%d (%s)",
                       err, strerror(err));
        }

        char *ip;
        Newxz(ip, INET_ADDRSTRLEN + 1, char);

        if (inet_ntop(AF_INET,
                      &local.sin_addr,
                      ip,
                      INET_ADDRSTRLEN + 1) == NULL) {
            int err = errno;
            Safefree(ip);
            close(sock);
            Perl_croak("inet_ntop failed: errno=%d (%s)",
                       err, strerror(err));
        }

        close(sock);
        RETVAL = ip;
    OUTPUT:
        RETVAL

MODULE = GTKWin PACKAGE = Gtk::AlertDialog

Gtk::AlertDialog
new(SV *class, char *title, char *detail)
    CODE:
        RETVAL = gtk_alert_dialog_new(title);
        gtk_alert_dialog_set_detail(RETVAL, detail);
    OUTPUT:
        RETVAL

void
show(Gtk::AlertDialog self, Gtk::Window parent)
    CODE:
        gtk_alert_dialog_show(self, parent);

MODULE = GTKWin PACKAGE = Gtk::Overlay

Gtk::Overlay
new(...)
    CODE:
        RETVAL = GTK_OVERLAY (gtk_overlay_new());
        g_object_ref_sink(G_OBJECT (RETVAL));
    OUTPUT:
        RETVAL

void
add_overlay(Gtk::Overlay over, GtkWidget *child)
    CODE:
        gtk_overlay_add_overlay(over, child);

void
set_child(Gtk::Overlay over, GtkWidget *child)
    CODE:
        gtk_overlay_set_child(over, child);

MODULE = GTKWin PACKAGE = Gtk::Grid

Gtk::Grid
new(...)
    CODE:
        RETVAL = GTK_GRID (gtk_grid_new());
        g_object_ref_sink(RETVAL);
    OUTPUT:
        RETVAL

void
attach(Gtk::Grid self, Gtk::Widget widget, int column, int row, int width, int height)
    CODE:
        gtk_grid_attach(self, widget, column, row, width, height);

MODULE = GTKWin PACKAGE = Gtk::Label

Gtk::Label
new(SV *class, char *label)
    CODE:
        RETVAL = GTK_LABEL (gtk_label_new((char *)label));
        g_object_ref_sink(RETVAL);
    OUTPUT:
        RETVAL

INCLUDE: Constants.xsi

MODULE = GTKWin PACKAGE = Gtk::ApplicationWindow

Gtk::ApplicationWindow
new(SV *class, Gtk::Application app)
    CODE:
        RETVAL = GTK_APPLICATION_WINDOW (gtk_application_window_new(app));
        g_object_ref_sink(G_OBJECT (RETVAL));
    OUTPUT:
        RETVAL

MODULE = GTKWin PACKAGE = PCAP::Packet

void
DESTROY(PCAP::Packet packet)
    CODE:
        Safefree(packet);

char *
src_ip(PCAP::Packet packet)
    CODE:
        RETVAL = packet->src_ip;
    OUTPUT:
        RETVAL

char *
dst_ip(PCAP::Packet packet)
    CODE:
        RETVAL = packet->dst_ip;
    OUTPUT:
        RETVAL

unsigned short
src_port(PCAP::Packet packet)
    CODE:
        RETVAL = packet->src_port;
    OUTPUT:
        RETVAL

unsigned short
dst_port(PCAP::Packet packet)
    CODE:
        RETVAL = packet->dst_port;
    OUTPUT:
        RETVAL

SV *
payload(PCAP::Packet packet)
    CODE:
        RETVAL = newSVpv(packet->payload, (STRLEN) packet->payload_len);
    OUTPUT:
        RETVAL

MODULE = GTKWin PACKAGE = PCAP::Program

void
DESTROY(PCAP::Program self)
    CODE:
        pcap_freecode(self);
        free(self);

MODULE = GTKWin PACKAGE = PCAP::Handle

int
datalink(PCAP::Handle self)
    CODE:
        RETVAL = pcap_datalink(self);
    OUTPUT:
        RETVAL

PCAP::Program
compile(PCAP::Handle self, unsigned char *program, int optimize)
    CODE:
        RETVAL = malloc(sizeof *RETVAL);
        if (pcap_compile(self, RETVAL, program, optimize, PCAP_NETMASK_UNKNOWN) == -1) {
            Perl_croak("%s", pcap_geterr(self));
        }
    OUTPUT:
        RETVAL

void
set_filter(PCAP::Handle self, PCAP::Program program)
    CODE:
        if (pcap_setfilter(self, program) == -1) {
            Perl_croak("%s", pcap_geterr(self));
        }

void
set_direction(PCAP::Handle self, unsigned char *direction)
    CODE:
        if (0 != strcmp(direction, "out")) {
            Perl_croak("Direction not supported");
        }
        pcap_setdirection(self, PCAP_D_OUT);

void
loop(PCAP::Handle self, SV *coderef)
    CODE:
        if (!SvROK(coderef) ||
            SvTYPE(SvRV(coderef)) != SVt_PVCV)
        {
            Perl_croak(aTHX_ "loop() requires a CODE reference");
        }
        PCAPContext *ctx = malloc(sizeof(*ctx));
        ctx->callback = coderef;
        ctx->datalink = pcap_datalink(self);

        pcap_loop(self, -1, gtk_win_pcap_handler, (u_char *)ctx);
        free(ctx);

void
DESTROY(PCAP::Handle self)
    CODE:
        pcap_close(self);

MODULE = GTKWin PACKAGE = PCAP::If

PCAP::If
find_all_devs(...)
    CODE:
        char errbuf[PCAP_ERRBUF_SIZE];
        if (pcap_findalldevs(&RETVAL, errbuf) == -1) {
            Perl_croak("%s", errbuf);
        }
    OUTPUT:
        RETVAL

PCAP::Handle
open_live(PCAP::If self, char *listen_addr, int snaplen, int promisc, int to_ms)
    CODE:
        char errbuf[PCAP_ERRBUF_SIZE];
        pcap_if_t *dev = NULL;
        for (dev = self; dev; dev = dev->next) {
            pcap_addr_t *addr;
            if (dev->flags & PCAP_IF_LOOPBACK)
                continue;
            for (addr = dev->addresses; addr; addr = addr->next) {
                struct sockaddr_in *sin;
                if (addr->addr == NULL)
                    continue;
                if (addr->addr->sa_family != AF_INET)
                    continue;
                sin = (struct sockaddr_in *)addr->addr;
                if (strcmp(inet_ntoa(sin->sin_addr), listen_addr) == 0)
                    goto found;
            }
        }
        dev = NULL;
        found:
        if (dev == NULL) {
            Perl_croak("Interface not found");
        }
        RETVAL = pcap_open_live(dev->name, snaplen, promisc, to_ms, errbuf);
        if (RETVAL == NULL) {
            Perl_croak("%s", errbuf);
        }
    OUTPUT:
        RETVAL

void
DESTROY(PCAP::If self)
    CODE:
        pcap_freealldevs(self);

MODULE = GTKWin PACKAGE = Gtk::Editable

const char *
get_text(Gtk::Editable self)
    CODE:
        RETVAL = gtk_editable_get_text(self);
    OUTPUT:
        RETVAL

MODULE = GTKWin PACKAGE = Gtk::Entry

Gtk::Entry
new(...)
    CODE:
        RETVAL = GTK_ENTRY (gtk_entry_new());
        g_object_ref_sink(G_OBJECT (RETVAL));
    OUTPUT:
        RETVAL

MODULE = GTKWin PACKAGE = Gtk::CheckButton

Gtk::CheckButton
new(...)
    CODE:
        RETVAL = GTK_CHECK_BUTTON (gtk_check_button_new());
        g_object_ref_sink(G_OBJECT (RETVAL));
    OUTPUT:
        RETVAL

bool
get_active(Gtk::CheckButton self)
    CODE:
        RETVAL = gtk_check_button_get_active(self);
    OUTPUT:
        RETVAL

MODULE = GTKWin PACKAGE = Gtk::Button

void
set_label(Gtk::Button button, char *label)
    CODE:
        gtk_button_set_label(button, label);

Gtk::Button
new(SV *class, char *label)
    CODE:
        RETVAL = GTK_BUTTON (gtk_button_new_with_label(label));
        g_object_ref_sink(G_OBJECT (RETVAL));
    OUTPUT:
        RETVAL

MODULE = GTKWin PACKAGE = Gtk::Window

void
set_title(Gtk::Window self, char *title)
    CODE:
        gtk_window_set_title(self, title);

Gtk::Window
new(SV *class)
    CODE:
        RETVAL = GTK_WINDOW (gtk_window_new());
        g_object_ref_sink(G_OBJECT (RETVAL));
    OUTPUT:
        RETVAL

void
set_default_size(Gtk::Window win, int width, int height)
    CODE:
        gtk_window_set_default_size(win, width, height);

void
set_resizable(Gtk::Window win, int resizable)
    CODE:
        gtk_window_set_resizable(win, !!resizable);

void
set_child(Gtk::Window win, GtkWidget *child)
    CODE:
        gtk_window_set_child(win, child);

void
present(Gtk::Window win)
    CODE:
        gtk_window_present(win);

MODULE = GTKWin PACKAGE = Gtk::Box

Gtk::Box
new(SV *class, unsigned int orientation, int spacing)
    CODE:
        RETVAL = GTK_BOX (gtk_box_new(orientation, spacing));
        g_object_ref_sink(RETVAL);
    OUTPUT:
        RETVAL

MODULE = GTKWin PACKAGE = Gtk::Widget

void
add_css_class(Gtk::Widget widget, char *class)
    CODE:
        gtk_widget_add_css_class(widget, class);

Gdk::Display
get_display(Gtk::Widget widget)
    CODE:
        RETVAL = gtk_widget_get_display(widget);
        g_object_ref_sink(RETVAL);
    OUTPUT:
        RETVAL

void
set_valign(Gtk::Widget widget, unsigned int constant)
    CODE:
        gtk_widget_set_valign(widget, constant);

void
set_halign(Gtk::Widget widget, unsigned int constant)
    CODE:
        gtk_widget_set_halign(widget, constant);

MODULE = GTKWin PACKAGE = Gtk::Application

Gtk::Application
new(SV *class, char *app_name, size_t flags)
    CODE:
        RETVAL = GTK_APPLICATION (gtk_application_new(app_name, flags));
        g_object_ref_sink(G_OBJECT (RETVAL));
    OUTPUT:
        RETVAL

MODULE = GTKWin PACKAGE = Gio::Application

void
timeout_add(SV *class, unsigned int interval, SV *callback)
    CODE:
       if (!SvROK(callback) || SvTYPE(SvRV(callback)) != SVt_PVCV) {
            croak("callback must be a coderef");
        }

        SvREFCNT_inc(callback);

        g_timeout_add(
            interval,
            perl_timeout_func,
            callback
        );
 

void
run(Gio::Application app, ...)
    CODE:
        int argc = items - 1;
        char **argv = malloc((argc + 1) * sizeof(*argv));

        argv[0] = "app";

        for (int i = 1; i < argc; i++) {
            argv[i] = SvPV_nolen(ST(i));
        }

        argv[argc] = NULL;

        g_application_run(app, argc, argv);

        free(argv);

MODULE = GTKWin PACKAGE = Gio::File

Gio::File
new(SV *class, unsigned char *path)
    CODE:
        RETVAL = g_file_new_for_path(path);
        g_object_ref_sink(RETVAL);
    OUTPUT:
        RETVAL

MODULE = GTKWin PACKAGE = Gtk::Picture

Gtk::Picture
new(SV *class, Gdk::Texture texture)
    CODE:
        RETVAL = GTK_PICTURE (gtk_picture_new_for_paintable(GDK_PAINTABLE (texture)));
        g_object_ref_sink(RETVAL);
    OUTPUT:
        RETVAL

MODULE = GTKWin PACKAGE = Gtk::CssProvider

Gtk::CssProvider
new(...)
    CODE:
        RETVAL =  gtk_css_provider_new();
        g_object_ref_sink(RETVAL);
    OUTPUT:
        RETVAL

void
load_from_path(Gtk::CssProvider self, char *path)
    CODE:
        gtk_css_provider_load_from_path(self, path);

MODULE = GTKWin PACKAGE = Gdk::Display

void
add_css_provider(Gdk::Display self, Gtk::CssProvider provider, int priority)
    CODE:
        gtk_style_context_add_provider_for_display(self, GTK_STYLE_PROVIDER (provider), priority);

MODULE = GTKWin PACKAGE = Gdk::Texture

Gdk::Texture
new(SV *class, Gio::File file)
    CODE:
        GError *error = NULL;
        RETVAL = gdk_texture_new_from_file(file, &error);
        g_object_ref_sink(RETVAL);
        if (error != NULL) {
            Perl_croak(error->message);
        }
    OUTPUT:
        RETVAL

MODULE = GTKWin PACKAGE = G::Object

void
bind_property_full(G::Object self, char *self_property, G::Object target, char *target_property, int flags, SV *transform_to, SV *transform_from)
    CODE:
        BindingUserdata *userdata = malloc(sizeof *userdata);
        SvREFCNT_inc(transform_to);
        SvREFCNT_inc(transform_from);
        userdata->to = transform_to;
        userdata->from = transform_from;
        g_object_bind_property_full(self, self_property, target, target_property, flags, binding_callback_to, binding_callback_from, userdata, NULL);
        

void
connect(G::Object obj, SV *signal, SV *callback)
    CODE:
        if (!SvROK(callback) || SvTYPE(SvRV(callback)) != SVt_PVCV) {
            croak("callback must be a coderef");
        }

        SvREFCNT_inc(callback);

        g_signal_connect(
            obj,
            SvPV_nolen(signal),
            G_CALLBACK(perl_signal_callback),
            callback
        );

void
DESTROY(G::Object obj)
    CODE:
        if (obj) {
            g_object_unref(obj);
        }
