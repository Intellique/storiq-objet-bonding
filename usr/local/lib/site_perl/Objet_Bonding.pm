#!/usr/bin/perl
## ######### PROJECT NAME : ##########
##
## Objet_Bonding.pm for objet bonding
##
## ######### PROJECT DESCRIPTION : ###
##
## This object permits to create, modify and delete bonding.
##
## ###################################
##
## Made by Boutonnet Alexandre
## Login   <aboutonnet@intellique.com>
##
## Started on  Mon Aug 25 15:18:17 2008 Boutonnet Alexandre
## Last update Fri Apr 10 16:33:50 2009 Boutonnet Alexandre
##
## ###################################
##

use strict;
use warnings;

package Objet_Bonding;

use Data::Dumper;

use Objet_Conf;
use Objet_Logger;
use Lib_Bonding;
use Lib_Network;

my $CONFIG_FILE = '/etc/storiq/bonding.conf';
my $XMIT_OPT    = 'xmit_hash_policy';

# Fonction de creation de l'objet bonding.
# Cette fonction prend en parametre :
# 1. Une instance de l'objet logger (Optionnel)
sub new {
    my $OL = {};

    # Stockage du nom de l'objet
    $OL->{OBJNAME} = shift;

    # Recuperation de l'objet logger
    $OL->{LOGGER} = shift;

    # Si l'objet logger est absent, je le crée.
    my $err;
    if ( !$OL->{LOGGER} ) {
        ( $err, $OL->{LOGGER} ) = new Objet_Logger();
        return ( 1, "Unable to instanciate Objet_Logger : $OL->{LOGGER}" )
            if ($err);
        $OL->{LOGGER}->debug(
            "$OL->{OBJNAME} : new : $OL->{LOGGER} parametre is missing.");
    }
    unless ( ref( $OL->{LOGGER} ) eq "Objet_Logger" ) {
        ( $err, $OL->{LOGGER} ) = new Objet_Logger();
        return ( 1, "Unable to instanciate Objet_Logger : $OL->{LOGGER}" )
            if ($err);
        $OL->{LOGGER}->debug(
            "$OL->{OBJNAME} : new : $OL->{LOGGER} isn't an Objet_Logger");
    }

    # J'ouvre mon fichier de conf grace a objet conf
    ( $err, $OL->{CONF} ) =
        new Objet_Conf( $CONFIG_FILE, $OL->{LOGGER}, "=", "#" );
    return ( 1, "Unable to instanciate Objet_Conf : $OL->{CONF}" ) if ($err);

    bless($OL);
    return ( 0, $OL );
}

# Fonction de recuperation d infos
# Cette fonction ne prend pas de paramètre
# Cette fonction retourne (0,$hash) en cas de succes
# et (1, $error_msg) en cas d'echec
sub status {
    my $status = {};
    my ( $error, $tab ) = Lib_Bonding::get_masters();
    print_and_exit($tab) if ($error);

    foreach my $bond ( @{$tab} ) {
        ( $error, $tab ) = Lib_Bonding::get_mode($bond);
        print_and_exit($tab) if ($error);

        $status->{$bond}->{'Mode'} = $tab->[0];

        ( $error, $tab ) = Lib_Bonding::get_iface($bond);
        print_and_exit($tab) if ($error);

        $status->{$bond}->{'Slaves'} = $tab;
        $status->{$bond}->{'Status'} = "down";

        if ( Lib_Network::get_if_status($bond) ) {
            $status->{$bond}->{'Status'} = "up";

            my $ref = Lib_Network::get_ifaces_info($bond);
            if ( defined( $ref->{$bond}->{'ifconfig'}->{'ip'} ) ) {
                $status->{$bond}->{'IP Address'} =
                    $ref->{$bond}->{ifconfig}->{ip};
            }
        }
    }

    return ( 0, $status );
}

# Fonction de creation d'un bond
# Cette fonction prend en parametre le nom du bond
# Cette fonction retour (0,0) en cas de succes
# et (1, $error_msg) en cas d'echec
sub create {
    my $OL = shift;

    # Je recup le nom de mon bond et le mode (optionnel)
    my ( $bond, $mode ) = @_;

    return ( 1, "Parameter is missing or invalid" ) if ( !$bond );

    # Verification du mode
    if ($mode) {
        my ( $err_mode, $msg_mode ) = Lib_Bonding::check_bond_mode($mode);
        if ($err_mode) {
            _log_error_msg( $OL,
                "$mode mode is invalid for $bond : " . $msg_mode );
            return ( $err_mode, $msg_mode );
        }
    }

    # Verification de l'existence du bond..
    if ( _check_existing_bond( $OL, $bond ) ) {
        _log_error_msg( $OL, "Bond $bond already exists in config file." );
        return ( 1, "Bond $bond already exists in config file." );
    }

    my $err;
    my $err_msg;

    ( $err, $err_msg ) = Lib_Bonding::add_master($bond);
    if ($err) {
        _log_error_msg( $OL, "Unable to add $bond bond in masters file." );
        return ( $err, $err_msg );
    }
    _log_info_msg( $OL, "Bond $bond added in masters file." );

    if ($mode) {
        ( $err, $err_msg ) = Lib_Bonding::set_mode( $bond, $mode );
        if ($err) {
            _log_error_msg( $OL,
                "Unable to set $mode mode to $bond : " . $err_msg );
            return ( $err, $err_msg );
        }
        _log_info_msg( $OL, "$bond bond mode is $mode." );
    }

    # Je cree mon entree dans le fichier de conf
    if ($mode) {
        ( $err, $err_msg ) = $OL->{CONF}->set_value( "mode", $mode, $bond );
    }
    else {
        ( $err, $err_msg ) =
            $OL->{CONF}->set_value( "mode", "balance-rr", $bond );
    }
    return ( $err, $err_msg ) if ($err);

    # Je set un miimon par defaut
    ( $err, $err_msg ) = $OL->{CONF}->set_value( "miimon", "100", $bond );
    return ( $err, $err_msg ) if ($err);

    # J'enregistre mon fichier
    ( $err, $err_msg ) = $OL->{CONF}->save();
    return ( $err, $err_msg ) if ($err);

    return ( 0, 0 );
}

# Fonction de suppression d'un bond
# Cette fonction prend en parametre le nom du bond
# Cette fonction retour (0,0) en cas de succes
# et (1, $error_msg) en cas d'echec
sub delete {
    my $OL = shift;

    # Je recup le nom de mon bond et le mode (optionnel)
    my $bond = shift;
    return ( 1, "Parameter is missing or invalid" ) if ( !$bond );

    my ( $err, $err_msg ) = Lib_Bonding::del_master($bond);
    if ($err) {
        _log_error_msg( $OL, "Unable to remove $bond bond in masters file." );
        return ( $err, $err_msg );
    }
    _log_info_msg( $OL, "$bond bond removed in masters file." );

    # Recuperation de la liste des sections :
    ( $err, $err_msg ) = $OL->{CONF}->delete_section($bond);
    return ( $err,
              "Unable to delete Bond " 
            . $bond . " : " 
            . $err_msg
            . " in config file" )
        if ($err);

    # J'enregistre mon fichier
    ( $err, $err_msg ) = $OL->{CONF}->save();
    return ( $err, $err_msg ) if ($err);

    return ( 0, 0 );
}

# Fonction d'ajout d'une ou plusieurs interfaces dans un bond
# Cette fonction prend en parametre le bond et une liste d'interfaces
# Cette fonction retour (0,0) en cas de succes
# et (1, $error_msg) en cas d'echec
sub add_if {
    my $OL = shift;

    # Je recup la liste des interfaces..
    my $bond   = shift;
    my @ifaces = @_;
    return ( 1, "Bond name parameter is missing or invalid" ) if ( !$bond );
    return ( 1, "Ifaces list parameter is missing or invalid" )
        if ( !@ifaces );

    # Verification de l'existence du bond..
    if ( !_check_existing_bond( $OL, $bond ) ) {
        _log_error_msg( $OL, "$bond bond does not exist in config file." );
        return ( 1, "$bond bond does not exist in config file." );
    }

    my @tmp_tab;

    my ( $err, $list ) = $OL->{CONF}->get_value( "slaves", $bond );

    # Si je recupere $err, c'est surement parce que j'ai pas encore de slaves
    if ($err) {
        $list = join( ' ', @ifaces );
        @tmp_tab = @ifaces;
    }
    else {

        # Ici correction du bug #281
        my @tab_list = split( ' ', $list );
        foreach my $iface (@ifaces) {
            if ( !grep( /^$iface$/, @tab_list ) ) {
                push( @tmp_tab,  $iface );
                push( @tab_list, $iface );
            }
        }
        $list = join( ' ', @tab_list );
    }

    my $err_msg;
    ( $err, $err_msg ) = Lib_Bonding::add_iface( $bond, \@tmp_tab );
    if ($err) {
        _log_error_msg( $OL,
            "Unable to add network interface(s) ($list) to $bond bond : "
                . $err_msg );
        return ( $err, $err_msg );
    }
    _log_info_msg( $OL, "$list network interface(s) added to $bond bond." );

    ( $err, $err_msg ) = $OL->{CONF}->set_value( "slaves", $list, $bond );
    return ( 1, $err_msg ) if ($err);

    # J'enregistre mon fichier
    ( $err, $err_msg ) = $OL->{CONF}->save();
    return ( 1, $err_msg ) if ($err);

    return ( 0, 0 );
}

# Fonction de suppression d'une ou plusieurs interfaces dans un bond
# Cette fonction prend en parametre le bond et une liste d'interfaces
# Cette fonction retour (0,0) en cas de succes
# et (1, $error_msg) en cas d'echec
sub del_if {
    my $OL = shift;

    # Je recup la liste des interfaces..
    my $bond   = shift;
    my @ifaces = @_;
    return ( 1, "Bond name parameter is missing or invalid" ) if ( !$bond );
    return ( 1, "Ifaces list parameter is missing or invalid" )
        if ( !@ifaces );

    # Verification de l'existence du bond..
    if ( !_check_existing_bond( $OL, $bond ) ) {
        _log_error_msg( $OL, "$bond bond does not exist in config file." );
        return ( 1, "$bond bond does not exist in config file." );
    }

    my ( $err, $list ) = $OL->{CONF}->get_value( "slaves", $bond );

    # Si je recupere $err, c'est que je n'ai pas de slave configure
    return ( 1, "No slave found in config file" ) if ($err);

    my @new_list;
    my @rm_list;
    my @tab_list = split( ' ', $list );

    foreach my $iface (@tab_list) {
        if ( !grep( /^$iface$/, @ifaces ) ) {
            push( @new_list, $iface );
        }
        else {
            push( @rm_list, $iface );
        }
    }
    $list = join( ' ', @new_list );

    my $err_msg;
    ( $err, $err_msg ) = Lib_Bonding::del_iface( $bond, \@rm_list );
    if ($err) {
        _log_error_msg( $OL,
            "Unable to delete network interface(s) ($list) from $bond bond : "
                . $err_msg );
        return ( $err, $err_msg );
    }
    _log_info_msg( $OL,
        "$list network interface(s) removed from $bond bond." );

    ( $err, $err_msg ) = $OL->{CONF}->set_value( "slaves", $list, $bond );
    return ( 1, $err_msg ) if ($err);

    # J'enregistre mon fichier
    ( $err, $err_msg ) = $OL->{CONF}->save();
    return ( 1, $err_msg ) if ($err);

    return ( 0, 0 );
}

# Fonction de parametrage du mode d'un bond
# Cette fonction prend en parametre le bond et le mode
# Cette fonction retour (0,0) en cas de succes
# et (1, $error_msg) en cas d'echec
sub set_mode {
    my $OL = shift;

    # Je recup la liste des interfaces..
    my $bond = shift;
    my $mode = shift;
    return ( 1, "Bond name parameter is missing or invalid" ) if ( !$bond );
    return ( 1, "Bond mode parameter is missing or invalid" ) if ( !$mode );

    # Verification de l'existence du bond..
    if ( !_check_existing_bond( $OL, $bond ) ) {
        _log_error_msg( $OL, "$bond bond does not exist in config file." );
        return ( 1, "$bond bond does not exist in config file." );
    }

    # Verification du mode
    my ( $err_mode, $msg_mode ) = Lib_Bonding::check_bond_mode($mode);
    if ($err_mode) {
        _log_error_msg( $OL,
            "$mode mode is invalid for $bond bond : " . $msg_mode );
        return ( $err_mode, $msg_mode );
    }

    my $err;
    my $err_msg;
    ( $err, $err_msg ) = Lib_Bonding::set_mode( $bond, $mode );
    if ($err) {
        _log_error_msg( $OL,
            "Unable to set $mode mode to $bond bond : " . $err_msg );
        return ( $err, $err_msg );
    }
    _log_info_msg( $OL, "$bond bond mode is $mode." );

    ( $err, $err_msg ) = $OL->{CONF}->set_value( "mode", $mode, $bond );
    return ( 1, $err_msg ) if ($err);

    # J'enregistre mon fichier
    ( $err, $err_msg ) = $OL->{CONF}->save();
    return ( 1, $err_msg ) if ($err);

    return ( 0, 0 );
}

# Fonction de parametrage d'un option d'un bond
# Cette fonction prend en parametre le bond, l'option et la valeur
# Cette fonction retourne (0,0) en cas de succes
# et (1, $error_msg) en cas d'echec
sub set_option {
    my $OL = shift;

    # Je recup la liste des interfaces..
    my ( $bond, $opt, $value ) = @_;
    return ( 1, "Bond name parameter is missing or invalid" )   if ( !$bond );
    return ( 1, "Option name parameter is missing or invalid" ) if ( !$opt );
    return ( 1, "Option value parameter is missing or invalid" )
        if ( !$value );

    # Verification de l'existence du bond..
    if ( !_check_existing_bond( $OL, $bond ) ) {
        _log_error_msg( $OL, "$bond bond does not exist in config file." );
        return ( 1, "$bond bond does not exist in config file." );
    }

    my $err;
    my $err_msg;

    if ( $opt eq $XMIT_OPT ) {
        ( $err, $err_msg ) =
            Lib_Bonding::set_xmit_hash_policy( $bond, $value );
    }
    else {
        ( $err, $err_msg ) = Lib_Bonding::set_option( $bond, $opt, $value );
    }

    if ($err) {
        _log_error_msg( $OL,
            "Unable to set $opt option (with $value value) to $bond bond." );
        return ( $err, $err_msg );
    }
    _log_info_msg( $OL, "$opt option set to $value to $bond bond." );

    ( $err, $err_msg ) = $OL->{CONF}->set_value( $opt, $value, $bond );
    return ( $err, $err_msg ) if ($err);

    # J'enregistre mon fichier
    ( $err, $err_msg ) = $OL->{CONF}->save();
    return ( $err, $err_msg ) if ($err);

    return ( 0, 0 );
}

# Fonction de demarrage d'un bond
# Cette fonction prend en parametre le nom du bond.
# Cette fonction retourne (0,0) en cas de succes
# et (1, $error_msg) en cas d'echec
sub start {
    my $OL = shift;

    # Je recup la liste des interfaces..
    my ($bond) = @_;
    return ( 1, "Bond name parameter is missing or invalid" ) if ( !$bond );

    # Verification de l'existence du bond..
    if ( !_check_existing_bond( $OL, $bond ) ) {
        _log_error_msg( $OL, "$bond bond does not exist in config file." );
        return ( 1, "$bond bond does not exist in config file." );
    }

    my ( $err, $keys_tab ) = $OL->{CONF}->get_key($bond);
    return ( 1, $keys_tab ) if ($err);

    my $err_msg;
    my $value;

    # Je dois gerer le mode avant tout (pb avec l'option
    # xmit_hash_policy)
    if ( grep( /^mode$/, @{$keys_tab} ) ) {
        ( $err, $value ) = $OL->{CONF}->get_value( "mode", $bond );
        return ( 1, $value ) if ($err);

        # Verification du mode
        my ( $err_mode, $msg_mode ) = Lib_Bonding::check_bond_mode($value);
        if ($err_mode) {
            _log_error_msg( $OL,
                "$value mode is invalid for $bond bond : " . $msg_mode );
            return ( $err_mode, $msg_mode );
        }

        ( $err, $err_msg ) = Lib_Bonding::set_mode( $bond, $value );
        if ($err) {
            _log_error_msg( $OL,
                "Unable to set $value mode to $bond bond : " . $err_msg );
            return ( $err, $err_msg );
        }
        _log_info_msg( $OL, "$bond bond mode is $value." );
    }

    # Boucle sur toutes les options dans mon fichier de conf
    # et je les set selon leur nature
	# les slaves en tout dernier!
	my @slaves;
    foreach my $key ( @{$keys_tab} ) {
        ( $err, $value ) = $OL->{CONF}->get_value( $key, $bond );
        return ( 1, $value ) if ($err);
		
        if ( $key eq "mode" ) {
            # le mode est deja gere au dessus.. je zappe
            next;
        }
        elsif ( $key eq "slaves" ) {
            my @tab_list = split( ' ', $value );
            # Boucler ici pour sauter celles deja configurees
            my ( $err_iface, $iface_tab ) = Lib_Bonding::get_iface($bond);
            return ( 1, $iface_tab ) if ($err_iface);

            foreach my $iface (@tab_list) {
                if ( !grep( /^$iface$/, @{$iface_tab} ) ) {
                    push( @slaves, $iface );
                }
            }
        }
        elsif ( $key eq "xmit_hash_policy" ) {
            ( $err, $err_msg ) =
                Lib_Bonding::set_xmit_hash_policy( $bond, $value );
        }
        else {
            ( $err, $err_msg ) =
                Lib_Bonding::set_option( $bond, $key, $value );
        }
		# enfin on declare les slaves
        ( $err, $err_msg ) = Lib_Bonding::add_iface( $bond, \@slaves )
            if (@slaves);

        if ($err) {
            _log_error_msg( $OL,
                "Start : Unable to set $key with '$value' value : "
                    . $err_msg );
            return ( $err, $err_msg );
        }
        _log_info_msg( $OL, "Start : Set $key with '$value' value." );
    }

    return ( 0, 0 );
}

# Fonction d'arret d'un bond
# Cette fonction prend en parametre le nom du bond.
# Cette fonction retourne (0,0) en cas de succes
# et (1, $error_msg) en cas d'echec
sub stop {
    my $OL = shift;

    # Je recup la liste des interfaces..
    my ($bond) = @_;
    return ( 1, "Bond name parameter is missing or invalid" ) if ( !$bond );

    # Verification de l'existence du bond..
    if ( !_check_existing_bond( $OL, $bond ) ) {
        _log_error_msg( $OL, "$bond bond does not exist in config file." );
        return ( 1, "$bond bond does not exist in config file." );
    }

    # Suppression des interfaces du bonding.

    my ( $err_iface, $iface_tab ) = Lib_Bonding::get_iface($bond);
    return ( 1, $iface_tab ) if ($err_iface);

    my ( $err, $err_msg ) = Lib_Bonding::del_iface( $bond, $iface_tab );
    if ($err) {
        _log_error_msg( $OL,
            "Unable to delete $bond bond from masters file : " . $err_msg );
        return ( $err, $err_msg );
    }
    _log_info_msg( $OL,
        "Successfull deletion of $bond bond from masters file." );

    ( $err, $err_msg ) = Lib_Network::ifdown($bond);
    return ( $err, $err_msg ) if ($err);

    return ( 0, 0 );
}

# Fonction d'initialisation d'un bond
# Cette fonction prend en parametre le nom du bond.
# Cette fonction retourne (0,0) en cas de succes
# et (1, $error_msg) en cas d'echec
sub init {
    my $OL = shift;

    # Je recup la liste des interfaces..
    my ($bond) = @_;
    return ( 1, "Bond name parameter is missing or invalid" ) if ( !$bond );

    # Verification de l'existence du bond..
    if ( !_check_existing_bond( $OL, $bond ) ) {
        _log_error_msg( $OL, "$bond bond does not exist in config file." );
        return ( 1, "$bond bond does not exist in config file." );
    }

    my ( $err, $err_msg ) = Lib_Bonding::add_master($bond);
    if ($err) {
        _log_error_msg( $OL,
            "Fail to add $bond bond in masters file : " . $err_msg );
        return ( $err, $err_msg );
    }
    _log_info_msg( $OL, "Bond $bond added in masters file." );

    return ( 0, 0 );
}

# liste les bonds definis dans le fichier de conf
sub list_bonds {
	    my $OL = shift;
		my @bonds = grep { ! m/DEFAUTINTELLIQUEUNIQUE/ } keys(%{$OL->{CONF}{CONF}}) ;
		return ( 0 , \@bonds);		
}

##### FONCTIONS TRANSPARENTES ####
sub get_masters {
    return Lib_Bonding::get_masters();
}

sub get_iface {
    my $OL   = shift;
    my $bond = shift;
    return Lib_Bonding::get_iface($bond);
}

##### PRIVATE FUNCTIONS ####

# Fonction de verification de l'existance d'un bond
# Retour 1 si oui et 0 si non
sub _check_existing_bond {
    my ( $OL, $bond ) = @_;

    # Recuperation de la liste des sections :
    my ( $err, @tab_sections ) = $OL->{CONF}->get_section();

    # Verification de l'existence du bond
    foreach my $exists_bond (@tab_sections) {
        return (1) if ( $exists_bond eq $bond );
    }

    return (0);
}

sub _log_info_msg {
    my ( $OL, $msg ) = @_;

    $OL->{LOGGER}->info( "Objet_Bonding : " . $msg );

    return (0);
}

sub _log_error_msg {
    my ( $OL, $msg ) = @_;

    $OL->{LOGGER}->error( "Objet_Bonding : " . $msg );

    return (0);
}

1;
 
