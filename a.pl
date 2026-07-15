use v5.38.0;
use strict;
use warnings;

use blib;

use GTK::Win;

use Moo;

has const => (is => 'lazy');
has app => (is => 'lazy');
has _grid_row => (is => 'rw', default => sub { 0 });

sub activate($self) {
    my $const = $self->const;
    my $win = Gtk::ApplicationWindow->new($self->app);
    $win->set_title("Front Proxy");
    my $display  = $win->get_display;
    my $provider = Gtk::CssProvider->new;
    $provider->load_from_path('style.css');
    $display->add_css_provider( $provider,
        $const->GTK_STYLE_PROVIDER_PRIORITY_APPLICATION );
    my $width  = 800;
    my $height = ( 1080 * 800 ) / 1920;
    say $height;
    $win->set_default_size( $width, $height );
    $win->set_resizable(0);
    my $overlay = Gtk::Overlay->new;
    my $file    = Gio::File->new('battlefrontii.jpg');
    my $texture = Gdk::Texture->new($file);
    my $picture = Gtk::Picture->new($texture);
    my $grid    = Gtk::Grid->new;
    $grid->add_css_class('transparent_background');
    $overlay->set_child($picture);
    $overlay->add_overlay($grid);
    my $server_entry   = Gtk::Entry->new;
    my $is_local_check = Gtk::CheckButton->new;
    $is_local_check->set_halign( $const->GTK_ALIGN_START );
    $self->call_and_increment_grid_row(sub {
        my $label = Gtk::Label->new('Proxy Star Wars Battlefront™');
        $label->add_css_class('title-1');
        $grid->attach($label, 0, $self->_grid_row, 3, 1);
    });
    $self->call_and_increment_grid_row(sub {
        $grid->attach( Gtk::Label->new('Is the server in this computer?'),
            0, $self->_grid_row, 1, 1 );
        $grid->attach( $is_local_check, 1, $self->_grid_row, 1, 1 );
    });
    my $label_proxy_server = Gtk::Label->new('Proxy for others in your lan in server direction?');
    my $label_server_ip = Gtk::Label->new('Server IP');
    my $negate_callback = sub {
        my $from = shift;
        return !$from;
    };
    my $proxy_others = Gtk::CheckButton->new;
    $is_local_check->bind_property_full(active => $label_proxy_server => visible => $const->G_BINDING_DEFAULT, $negate_callback, undef);
    $is_local_check->bind_property_full(active => $proxy_others => visible => $const->G_BINDING_DEFAULT, $negate_callback, undef);
    $is_local_check->bind_property_full(active => $label_server_ip => visible => $const->G_BINDING_DEFAULT, $negate_callback, undef);
    $is_local_check->bind_property_full(active => $server_entry => visible => $const->G_BINDING_DEFAULT, $negate_callback, undef);
    $proxy_others->set_halign( $const->GTK_ALIGN_START );
    $self->call_and_increment_grid_row(sub {
        $grid->attach(
            $label_proxy_server,
            0, $self->_grid_row, 1, 1 );
        $grid->attach( $proxy_others, 1, $self->_grid_row, 1, 1 );
    });

    $self->call_and_increment_grid_row(sub {
        $grid->attach( $label_server_ip,    0, $self->_grid_row, 1, 1 );
        $grid->attach( $server_entry,                   1, $self->_grid_row, 1, 1 );
    });
    $self->call_and_increment_grid_row(sub {
        $grid->attach( Gtk::Button->new("Start Proxy"), 1, $self->_grid_row, 1, 1 );
    });
    $grid->set_valign( $const->GTK_ALIGN_CENTER );
    $grid->set_halign( $const->GTK_ALIGN_CENTER );
    $win->set_child($overlay);
    $win->present;
}

sub call_and_increment_grid_row($self, $coderef) {
    $coderef->();
    $self->_grid_row($self->_grid_row+1);
}

sub _build_app {
    return Gtk::Application->new( "me.sergiotarxz.hola", 0 );
}

sub _build_const {
    return Gtk::Win::Constants->new;
}

sub run($self) {
    $self->app->connect(
        'activate' => sub {
            $self->activate;
        }
    );

    $self->app->run(@ARGV);
}

__PACKAGE__->new->run;

#for my $ip (qw/192.168.1.96 192.168.2.38/) {
#    my $devs    = PCAP::If->find_all_devs();
#    my $handle  = $devs->open_live( $ip, 65535, 1, 10 );
#    my $program = $handle->compile(
#'udp and (dst host 192.168.2.38 or dst host 255.255.255.255 or dst host 192.168.1.96) and (src port 3659 or dst port 3659 or src port 3658 or src port 3656 or dst port 3658 or dst port 3656)',
#        1
#    );
#    $handle->set_filter($program);
#    say $handle->datalink;
#    next if fork;
#    $handle->loop(
#        sub ($packet) {
#use IO::Socket::INET;
##                say $packet->src_ip . ':' . $packet->src_port;
##                say $packet->dst_ip . ':' . $packet->dst_port;
#
#            state %sockets;
#            if ( $packet->dst_ip eq '192.168.2.38' || $packet->dst_ip eq '255.255.255.255' || $packet->dst_ip eq '192.168.1.96') {
#                if ($ip eq '192.168.2.38') {
##                    say 'VPN';
#                    my $sock = $sockets{$packet->src_ip.'.'.$packet->src_port} // IO::Socket::INET->new(
#                        Proto     => 'udp',
#                        PeerAddr  => '192.168.1.89',
#                        PeerPort  => $packet->dst_port,
#                        LocalAddr => '192.168.1.96',
#                        LocalPort => $packet->src_port,
#                        ReusePort => 1
#                    ) or die "$!";
#                    $sock->blocking(0);
#                    $sockets{$packet->src_ip.'.'.$packet->src_port} = $sock;
#                    $sock->send($packet->payload);
#               } else {
##                    say 'ETH';
#                    my $sock = $sockets{$packet->src_ip.'.'.$packet->src_port} // IO::Socket::INET->new(
#                        Proto     => 'udp',
#                        PeerAddr  => '192.168.2.1',
#                        PeerPort  => $packet->dst_port,
#                        LocalAddr => '192.168.2.38',
#                        LocalPort => $packet->src_port,
#                        ReusePort => 1
#                    ) or die "$!";
#                    #say 'hola';
#                    $sock->blocking(0);
#                    $sockets{$packet->src_ip.'.'.$packet->src_port} = $sock;
#                    $sock->send($packet->payload);
#                }
#            }
#        }
#    );
#    exit 0;
#}
#<>;
