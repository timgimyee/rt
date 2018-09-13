use strict;
use warnings;

use RT::Test tests => undef;

RT::Config->Set( 'ShredderStoragePath', RT::Test->temp_directory . '' );

my ( $baseurl, $agent ) = RT::Test->started_ok;

diag("Test server running at $baseurl");
my $url = $agent->rt_base_url;

# Login
$agent->login( 'root' => 'password' );

# Anonymize User
{
    my $user = RT::Test->load_or_create_user( Name => 'Test User' );
    ok $user && $user->id;

    my $user_id = $user->id;

    $agent->get_ok( $url . "Admin/Users/Modify.html?id=" . $user_id );
    $agent->follow_link_ok( { text => 'Anonymize' } );

    $agent->submit_form_ok( { form_id => 'user-info-modal', },
        "Anonymize user" );

    $user->Load($user_id);
    is $user->EmailAddress, '', 'User Email removed';

# UserId is still the same, but all other records should be anonimyzed for TestUser
    my ( $ret, $msg ) = $user->Load($user_id);
    ok $ret;

    is $user->Name =~ /anon_/, 1, 'Username replaced with anon name';

    my @user_idenifying_info = qw (
        Address1 Address2 City Comments Country EmailAddress
        FreeformContactInfo Gecos HomePhone MobilePhone NickName Organization
        PagerPhone RealName Signature SMIMECertificate State Timezone WorkPhone Zip
        );
    $user->Load($user_id);

    # Ensure that all other user fields are blank
    foreach my $attr (@user_idenifying_info) {
        my $check = grep { not defined $_ or $_ eq '' or $_ eq 0 } $user->$attr;
        is $check, 1, 'Attribute ' . $attr . ' is blank';
    }

    # Test that customfield values are removed with anonymize user action
    my $customfield = RT::CustomField->new( RT->SystemUser );
    ( $ret, $msg ) = $customfield->Create(
        Name       => 'TestCustomfield',
        LookupType => 'RT::User',
        Type       => 'FreeformSingle',
    );
    ok $ret, $msg;

    ( $ret, $msg ) = $customfield->AddToObject($user);
    ok( $ret, "Added CF to user object - " . $msg );

    ( $ret, $msg ) = $user->AddCustomFieldValue(
        Field => 'TestCustomfield',
        Value => 'Testing'
    );
    ok $ret, $msg;

    is $user->FirstCustomFieldValue('TestCustomfield'), 'Testing',
        'Customfield exists and has value for user.';

    $agent->get_ok( $url . "Admin/Users/Modify.html?id=" . $user->id );
    $agent->follow_link_ok( { text => 'Anonymize' } );

    $agent->submit_form_ok(
        {   form_id => 'user-info-modal',
            fields  => { clear_customfields => 'On' },
        },
        "Anonymize user and customfields"
    );

    is $user->FirstCustomFieldValue('TestCustomfield'), undef,
        'Customfield value cleared';
}

# Test replace user
{
    my $user = RT::Test->load_or_create_user(
        Name       => 'user',
        Password   => 'password',
        Privileged => 1
    );
    ok $user && $user->id;

    ok( RT::Test->set_rights(
            { Principal => $user, Right => [qw(SuperUser)] },
        ),
        'set rights'
      );

    ok $agent->logout;
    ok $agent->login( 'root' => 'password' );

    $agent->get_ok( $url . "Admin/Users/Modify.html?id=" . $user->id );
    $agent->follow_link_ok( { text => 'Replace' } );

    $agent->submit_form_ok(
        {   form_id => 'shredder-search-form',
            fields  => { WipeoutObject => 'RT::User-' . $user->Name, },
            button  => 'Wipeout'
        },
        "Replace user"
    );

    my ($ret, $msg) = $user->Load($user->Id);

    is $ret, 0,
        'User successfully deleted with replace';
}

# Test Remove user
{
    my $user = RT::Test->load_or_create_user(
        Name       => 'user',
        Password   => 'password',
        Privileged => 1
    );
    ok $user && $user->id;

    ok( RT::Test->set_rights(
            { Principal => $user, Right => [qw(SuperUser)] },
        ),
        'set rights'
      );

    $agent->logout;
    $agent->login( 'root' => 'password' );

    $agent->get_ok( $url . "Admin/Users/Modify.html?id=" . $user->id );
    $agent->follow_link_ok( { text => 'Remove' } );

    $agent->submit_form_ok(
        {   form_id => 'shredder-search-form',
            fields  => { WipeoutObject => 'RT::User-' . $user->Name, },
            button  => 'Wipeout'
        },
        "Remove user"
    );

    my ($ret, $msg) = $user->Load($user->Id);

    is $ret, 0,
        'User successfully deleted with remove';
}

done_testing();
