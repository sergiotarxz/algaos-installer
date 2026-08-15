package AlgaOS::Installer::GUI;

use v5.40.0;
use strict;
use warnings;

use Moo;
use AlgaOS::Installer;
use AlgaOS::Installer::Util;

has app                     => ( is => 'lazy' );
has win                     => ( is => 'rw' );
has const                   => ( is => 'lazy' );
has pipe_name               => ( is => 'ro', required => 1 );
has secret                  => ( is => 'ro', required => 1 );
has _pending_client_packets => ( is => 'lazy' );
has _grid_row               => ( is => 'rw', default => sub { 0 } );
has _packet_handlers        => ( is => 'lazy' );
has _proxy_started          => ( is => 'rw' );
has _server_entry           => ( is => 'rw' );
has _is_local_check         => ( is => 'rw' );
has _start_proxy_button     => ( is => 'rw' );
has _proxy_others           => ( is => 'rw' );

sub _get_status_handler( $self, $client, $packet ) {
    $self->_start_proxy_button->set_label(
        !$packet->{started} ? 'Start Proxy' : 'End Proxy' );
    $self->_proxy_started( $packet->{started} );
    $self->app->timeout_add(
        1000,
        sub {
            push $self->_pending_client_packets->@*, {
                type     => 'GET_STATUS_PROXY',
                callback => sub( $client, $packet ) {
                    $self->_get_status_handler( $client, $packet );
                }
            };
            return 0;
        }
    );
}

sub _handle_packets_gui( $self, $client, $buf ) {
    state $stored_partial_message = "";
    return if !defined $buf;
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
        $return ? ($return) : ();
    } @messages;
    for my $packet (@packets) {
        $self->_handle_packet_gui( $client, $packet );
    }
}

sub _handle_packet_gui( $self, $client, $packet ) {

#    print Data::Dumper::Dumper $packet;
    my $serial   = $packet->{serial};
    my $callback = $self->_packet_handlers->{$serial};
    if ( defined $callback ) {
        $callback->( $client, $packet );
    }
}

sub _build__packet_handlers {
    return {};
}

sub call_and_increment_grid_row( $self, $coderef ) {
    $coderef->();
    $self->_grid_row( $self->_grid_row + 1 );
}

sub _add_packet_handler( $self, $serial, $callback ) {
    $self->_packet_handlers->{$serial} = $callback;
}

sub _build_const {
    return AlgaOS::Installer::Constants->new;
}

sub _build_app {
    return Gtk::Application->new( "me.sergiotarxz.hola", 0 );
}

sub _create_main_grid($self) {
    my $const = $self->const;
    my $grid  = Gtk::Grid->new;
    $grid->add_css_class('transparent_background');
    my $is_local_check = Gtk::CheckButton->new;
    $self->_is_local_check($is_local_check);
    $self->_is_local_check->set_halign( $const->GTK_ALIGN_START );
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
            $grid->attach( $self->_is_local_check, 1, $self->_grid_row, 1, 1 );
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
    $self->_proxy_others($proxy_others);
    $self->_is_local_check->bind_property_full(
        active => $label_proxy_server => visible => $const->G_BINDING_DEFAULT,
        $negate_callback, undef
    );
    $self->_is_local_check->bind_property_full(
        active  => $self->_proxy_others,
        visible => $const->G_BINDING_DEFAULT,
        $negate_callback, undef
    );
    $self->_is_local_check->bind_property_full(
        active => $label_server_ip => visible => $const->G_BINDING_DEFAULT,
        $negate_callback, undef
    );
    $self->_is_local_check->bind_property_full(
        active  => $self->_server_entry,
        visible => $const->G_BINDING_DEFAULT,
        $negate_callback, undef
    );
    $self->_proxy_others->set_halign( $const->GTK_ALIGN_START );
    $self->call_and_increment_grid_row(
        sub {
            $grid->attach( $label_proxy_server,  0, $self->_grid_row, 1, 1 );
            $grid->attach( $self->_proxy_others, 1, $self->_grid_row, 1, 1 );
        }
    );

    $self->call_and_increment_grid_row(
        sub {
            $grid->attach( $label_server_ip,     0, $self->_grid_row, 1, 1 );
            $grid->attach( $self->_server_entry, 1, $self->_grid_row, 1, 1 );
        }
    );
    $self->call_and_increment_grid_row(
        sub {
            $grid->attach( $self->_start_proxy_button,
                1, $self->_grid_row, 1, 1 );
        }
    );
    $self->_start_proxy_button->connect(
        clicked => sub {
            $self->_on_start_proxy_button_press;
        }
    );

    $grid->set_valign( $const->GTK_ALIGN_CENTER );
    $grid->set_halign( $const->GTK_ALIGN_CENTER );
    return $grid;
}

sub _on_start_proxy_button_press($self) {
    my $server_address = undef;
    my $interface_ip   = undef;
    my $is_local       = 0;
    if ( !$self->_is_local_check->get_active ) {
        $is_local       = 1;
        $server_address = $self->_server_entry->get_text;
        eval { $interface_ip = Front::Net::IfIp->to_reach($server_address); };
        if ($@) {
            my $dialog = Gtk::AlertDialog->new( "Error",
                "Unable to find route to server: $server_address" );
            $dialog->show( $self->win );
            return;
        }
    }

    if ( !$self->_proxy_started ) {
        push $self->_pending_client_packets->@*, {
            type           => 'START_PROXY',
            server_address => $server_address,
            interface_ip   => $interface_ip,
            is_local       => $self->_is_local_check->get_active,
            proxy_others   => $self->_proxy_others->get_active,
            callback       => sub( $client, $packet ) {
                my $message = $packet->{error} // $packet->{ok};
                my $title   = "On it";
                if ( defined $packet->{error} ) {
                    $title   = "Error";
                    $message = "Unable to start server: " . $message;
                }
                if (defined $message) {
                my $dialog = Gtk::AlertDialog->new( $title, $message );
                $dialog->show( $self->win );
}
            },
        };
    }
    else {
        push $self->_pending_client_packets->@*, { type => 'END PROXY', };
    }
}

sub activate($self) {
    my $const              = $self->const;
    my $win                = Gtk::ApplicationWindow->new( $self->app );
    my $start_proxy_button = Gtk::Button->new("Start Proxy");
    $self->_start_proxy_button($start_proxy_button);
    $win->set_title("Front Proxy");
    my $display  = $win->get_display;
    my $provider = Gtk::CssProvider->new;
    $provider->load_from_path('style.css');
    $display->add_css_provider( $provider,
        $const->GTK_STYLE_PROVIDER_PRIORITY_APPLICATION );
    my $width  = 800;
    my $height = ( 1080 * 800 ) / 1920;
    $win->set_default_size( $width, $height );
    $win->set_resizable(0);
    $self->win($win);
    my $overlay = Gtk::Overlay->new;
    my $file    = Gio::File->new('beach0.jpg');
    my $texture = Gdk::Texture->new($file);
    my $picture = Gtk::Picture->new($texture);
    $overlay->set_child($picture);
    my $server_entry = Gtk::Entry->new;
    $self->_server_entry($server_entry);
    $overlay->add_overlay( $self->_create_main_grid );
    $win->set_child($overlay);
    $win->present;
}

sub run($self) {
    $self->app->connect(
        'activate' => sub {
            $self->activate;
        }
    );

    $self->app->run(@ARGV);
}

sub _build__pending_client_packets {
    return [];
}
1;
