package AlgaOS::Installer::GUI;

use v5.40.0;
use strict;
use warnings;

use Moo;
use AlgaOS::Installer;
use AlgaOS::Installer::Util;
use List::Util;
use JSON;

has app                        => ( is => 'lazy' );
has win                        => ( is => 'rw' );
has const                      => ( is => 'lazy' );
has pipe_name                  => ( is => 'ro', required => 1 );
has secret                     => ( is => 'ro', required => 1 );
has _grid_row                  => ( is => 'rw', default  => sub { 0 } );
has _proxy_started             => ( is => 'rw' );
has _hostname_entry            => ( is => 'rw' );
has _username_entry            => ( is => 'rw' );
has _password_entry            => ( is => 'rw' );
has _start_installation_button => ( is => 'rw' );
has _proxy_others              => ( is => 'rw' );

sub call_and_increment_grid_row( $self, $coderef ) {
    $coderef->();
    $self->_grid_row( $self->_grid_row + 1 );
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
    $self->call_and_increment_grid_row(
        sub {
            my $label = Gtk::Label->new('Install AlgaOS');
            $label->add_css_class('title-1');
            $grid->attach( $label, 0, $self->_grid_row, 3, 1 );
        }
    );
    $self->call_and_increment_grid_row(
        sub {
            $grid->attach( Gtk::Label->new('Select hostname'),
                0, $self->_grid_row, 1, 1 );
            $grid->attach( $self->_hostname_entry, 1, $self->_grid_row, 1, 1 );
        }
    );
    $self->call_and_increment_grid_row(
        sub {
            $grid->attach( Gtk::Label->new('New user name'),
                0, $self->_grid_row, 1, 1 );
            $grid->attach( $self->_username_entry, 1, $self->_grid_row, 1, 1 );
        }
    );
    $self->call_and_increment_grid_row(
        sub {
            $grid->attach( Gtk::Label->new('New user password'),
                0, $self->_grid_row, 1, 1 );
            $grid->attach( $self->_password_entry, 1, $self->_grid_row, 1, 1 );
        }
    );

    my $is_national = sub {
        my $nation = shift;
        return List::Util::any { $_ eq $nation }
        (qw{Europe/Madrid Africa/Ceuta Atlantic/Canary});
    };

    my $is_europe = sub {
        my $region = shift;
        return $region =~ /Europe/;
    };

    $self->call_and_increment_grid_row(
        sub {
            $grid->attach( Gtk::Label->new('Set your timezone'),
                0, $self->_grid_row, 1, 1 );
            my @timezones = split /\s+/s, `timedatectl list-timezones`;
            @timezones = grep { defined $_ } @timezones;
            @timezones = sort {
                return
                     ( $b eq 'Europe/Madrid' ) <=> ( $a eq 'Europe/Madrid' )
                  || $is_national->($b)        <=> $is_national->($a)
                  || $is_europe->($b)          <=> $is_europe->($a)
                  || $a cmp $b;
            } @timezones;
            my $dropdown = Gtk::Dropdown->new( [@timezones] );
            $grid->attach( $dropdown, 1, $self->_grid_row, 1, 1 );
        }
    );

    my $is_spain_spanish = sub {
        my $lang = shift;
        return $lang =~ /^es_ES/;
    };
    my $is_spanish = sub {
        my $lang = shift;
        return $lang =~ /^es/;
    };
    my $is_english = sub {
        my $lang = shift;
        return $lang =~ /^en/;
    };
    $self->call_and_increment_grid_row(
        sub {
            $grid->attach( Gtk::Label->new('Set your language and region'),
                0, $self->_grid_row, 1, 1 );
            my @locales = split /\s+/s, `locale -a`;
            @locales = grep { defined $_ && $_ =~ /utf8/ } @locales;
            @locales = sort {
                return
                     $is_spain_spanish->($b) <=> $is_spain_spanish->($a)
                  || $is_spanish->($b)       <=> $is_spanish->($a)
                  || $is_english->($b)       <=> $is_english->($a)
                  || $a cmp $b;
            } @locales;
            my $dropdown = Gtk::Dropdown->new( [@locales] );
            $grid->attach( $dropdown, 1, $self->_grid_row, 1, 1 );
        }
    );
    $self->call_and_increment_grid_row(
        sub {
            $grid->attach( Gtk::Label->new('Set the installation destination'),
                0, $self->_grid_row, 1, 1 );
            my $block_devices = JSON::from_json(`lsblk --json -d -o NAME,SIZE,MODEL,TYPE,TRAN`);
            my @block_devices = map {
				join "\t", @$_{qw/name model size type tran/};
            } $block_devices->{blockdevices}->@*;
            @block_devices = grep { defined $_ } @block_devices;
            my $dropdown = Gtk::Dropdown->new( [@block_devices] );
            $grid->attach( $dropdown, 1, $self->_grid_row, 1, 1 );
        }
    );    

    $self->call_and_increment_grid_row(
        sub {
            $grid->attach( $self->_start_installation_button,
                1, $self->_grid_row, 1, 1 );
        }
    );
    $self->_start_installation_button->connect(
        clicked => sub {
        }
    );

    $grid->set_valign( $const->GTK_ALIGN_CENTER );
    $grid->set_halign( $const->GTK_ALIGN_CENTER );
    return $grid;
}

sub activate($self) {
    my $const                     = $self->const;
    my $win                       = Gtk::ApplicationWindow->new( $self->app );
    my $start_installation_button = Gtk::Button->new("Start installation");
    $self->_start_installation_button($start_installation_button);
    $win->set_title("Install AlgaOS");
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
    my $hostname_entry = Gtk::Entry->new;
    $self->_hostname_entry($hostname_entry);
    my $username_entry = Gtk::Entry->new;
    $self->_username_entry($username_entry);
    my $password_entry = Gtk::Entry->new;
    $self->_password_entry($password_entry);
    my $scroll = Gtk::ScrolledWindow->new;
    $scroll->set_child( $self->_create_main_grid );
    $overlay->add_overlay($scroll);
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
1;
