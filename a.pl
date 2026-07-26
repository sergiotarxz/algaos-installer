use v5.38.0;
use strict;
use warnings;

use blib;

use UV;
use UV::Loop;
use UV::Pipe;
use UV::Timer;
use JSON qw/from_json to_json/;

use GTK::Win;

use Moo;
use Crypt::URandom qw/urandom/;

has const          => ( is => 'lazy' );
has app            => ( is => 'lazy' );
has _grid_row      => ( is => 'rw', default => sub { 0 } );
has _proxy_started => ( is => 'rw' );
has _is_windows    => ( is => 'lazy' );
has _pipe_name     => ( is => 'lazy' );
has _secret        => ( is => 'lazy' );
has _clients       => ( is => 'lazy' );
has _clients_in_kind => (is => 'lazy' );

sub _build__clients {
    return {};
}

sub _build__clients_in_kind {
    return {
        GUI  => {},
        PCAP => {},
    };
}


my $ID_APP = 'FrontProxy';

sub _build__secret($self) {
    return urandom(64);
}

sub _build__pipe_name($self) {
    my $socket = "$ID_APP-$$";
    if ( $self->_is_windows ) {
        $socket = "\\\\.\\pipe\\$socket";
    }
    else {
        $socket = "/tmp/$socket.sock";
    }
    return $socket;
}

sub _start_server($self) {
    $self->_pipe_name;
    my $parent = $$;
    my $pid    = fork;
    if ( !$pid ) {
        my $loop  = UV::Loop->new;
        my $pipe  = UV::Pipe->new( loop => $loop );
        my $timer = UV::Timer->new(
            loop     => $loop,
            on_timer => sub {
                if ( !kill 0, $parent ) {
                    say 'Parent defunct exiting server';
                    exit;
                }
            }
        );
        $timer->start( 10, 10 );
        say "Listening in @{[$self->_pipe_name]}";
        $pipe->bind( $self->_pipe_name );
        $pipe->on(
            connection => sub {
                my $pipe   = shift;
                my $client = $pipe->accept;
                $self->_clients->{$client} = $client;
                $client->on(
                    read => sub {
                        my ( $client, $status, $buf ) = @_;
                        $self->_handle_packets_server($client, $buf);
                    }
                );
                $client->on(
                    close => sub($client) {
                        delete $self->_clients->{$client};
                        delete $self->_clients_in_kind->{GUI}{$client};
                        delete $self->_clients_in_kind->{PCAP}{$client};
                    }
                );
                $client->read_start;
            }
        );
        $pipe->listen(100);
        $loop->run(UV::Loop::UV_RUN_DEFAULT);
        exit;
    }
}

sub _handle_packet_server( $self, $client, $packet ) {
    state %valid_handle_types = (
        GUI => 1,
        PCAP => 1,
    );
    state %packet_resolution = (
        INIT => sub($self, $client, $packet) {
            my $client_type = $packet->{client_type};
            if (!defined $client_type || !$valid_handle_types{$client_type}) {
                $client->write(to_json({error => 'Invalid client kind'}), sub {});
                return;
            }
            $self->_clients_in_kind->{$client_type}{$client} = $client;
            $client->write(to_json({ok => 1}), sub {});
        }
    );
    if ( 'HASH' ne ref $packet ) {
        warn 'Invalid packet format';
        $client->write(to_json({error => 'Invalid packet format'}), sub {});
        return;
    }
    if (!defined $packet->{secret} || unpack('H*', $self->_secret) ne $packet->{secret}) {
        $client->write(to_json({error => 'Application secret not valid'}), sub {});
        return;
    }
    my $packet_type = $packet->{type};
    my $callback = $packet_resolution{$packet_type};
    if (!defined $callback) {
        $client->write(to_json({error => 'No packet type or no known action'}), sub {});
        return;
    }
    return defined $callback->($self, $client, $packet);
}

sub _handle_packets_server( $self, $client, $buf ) {
    state $stored_partial_message = "";
    my @messages = split "\n", $buf;
    if ( !@messages ) {
        warn "No messages, why are we here?";
        return;
    }
    $messages[0] = $stored_partial_message . $messages[0];
    $stored_partial_message = "";
    if ( $buf !~ /\n$/s ) {
        $stored_partial_message = pop @messages;
    }
    my @packets = map {
        my $return = eval { from_json($_) };
        if ($@) {
            $client->write(to_json({error => "No JSON: $@"}), sub {});
        }
        $return ? ($return) : ();
    } @messages;
    for my $packet (@packets) {
        $self->_handle_packet_server( $client, $packet );
    }
}

sub _build__is_windows {
    return $^O eq 'MSWin32';
}

sub activate($self) {
    my $const = $self->const;
    my $win   = Gtk::ApplicationWindow->new( $self->app );
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
    $self->app->timeout_add(100, sub {
        say 'hola';
        return 1;
    });
    my $is_local_check = Gtk::CheckButton->new;
    $is_local_check->set_halign( $const->GTK_ALIGN_START );
    $self->call_and_increment_grid_row(
        sub {
            my $label = Gtk::Label->new('Proxy Star Wars Battlefront™');
            $label->add_css_class('title-1');
            $grid->attach( $label, 0, $self->_grid_row, 3, 1 );
        }
    );
    $self->call_and_increment_grid_row(
        sub {
            $grid->attach( Gtk::Label->new('Is the server in this computer?'),
                0, $self->_grid_row, 1, 1 );
            $grid->attach( $is_local_check, 1, $self->_grid_row, 1, 1 );
        }
    );
    my $label_proxy_server =
      Gtk::Label->new('Proxy for others in your lan in server direction?');
    my $label_server_ip = Gtk::Label->new('Server IP');
    my $negate_callback = sub {
        my $from = shift;
        return !$from;
    };
    my $proxy_others = Gtk::CheckButton->new;
    $is_local_check->bind_property_full(
        active => $label_proxy_server => visible => $const->G_BINDING_DEFAULT,
        $negate_callback, undef
    );
    $is_local_check->bind_property_full(
        active => $proxy_others => visible => $const->G_BINDING_DEFAULT,
        $negate_callback, undef
    );
    $is_local_check->bind_property_full(
        active => $label_server_ip => visible => $const->G_BINDING_DEFAULT,
        $negate_callback, undef
    );
    $is_local_check->bind_property_full(
        active => $server_entry => visible => $const->G_BINDING_DEFAULT,
        $negate_callback, undef
    );
    my $start_proxy_button = Gtk::Button->new("Start Proxy");
    $proxy_others->set_halign( $const->GTK_ALIGN_START );
    $self->call_and_increment_grid_row(
        sub {
            $grid->attach( $label_proxy_server, 0, $self->_grid_row, 1, 1 );
            $grid->attach( $proxy_others,       1, $self->_grid_row, 1, 1 );
        }
    );

    $self->call_and_increment_grid_row(
        sub {
            $grid->attach( $label_server_ip, 0, $self->_grid_row, 1, 1 );
            $grid->attach( $server_entry,    1, $self->_grid_row, 1, 1 );
        }
    );
    $self->call_and_increment_grid_row(
        sub {
            $grid->attach( $start_proxy_button, 1, $self->_grid_row, 1, 1 );
        }
    );
    $start_proxy_button->connect(
        clicked => sub {
            my $server_address = $server_entry->get_text;
            my $interface_ip;
            eval {
                $interface_ip = Front::Net::IfIp->to_reach($server_address);
            };
            if ($@) {
                my $dialog = Gtk::AlertDialog->new( "Error",
                    "Unable to find route to server: $server_address" );
                $dialog->show($win);
            }
            $self->_proxy_started( !$self->_proxy_started );
            $start_proxy_button->set_label(
                $self->_proxy_started ? 'Start Proxy' : 'End Proxy' );
        }
    );
    $grid->set_valign( $const->GTK_ALIGN_CENTER );
    $grid->set_halign( $const->GTK_ALIGN_CENTER );
    $win->set_child($overlay);
    $win->present;
}

sub call_and_increment_grid_row( $self, $coderef ) {
    $coderef->();
    $self->_grid_row( $self->_grid_row + 1 );
}

sub _build_app {
    return Gtk::Application->new( "me.sergiotarxz.hola", 0 );
}

sub _build_const {
    return Gtk::Win::Constants->new;
}

sub run($self) {
    $self->_start_server;
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
