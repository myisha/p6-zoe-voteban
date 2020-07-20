#!perl6

use API::Discord;
use API::Discord::Permissions;

my Str $command-prefix = %*ENV<ZOE_VOTEBAN_COMMAND_PREFIX> || "+";
my Str $reaction-for-emote = %*ENV<ZOE_VOTEBAN_REACTION_FOR_EMOTE> || "✅";
my Str $reaction-against-emote = %*ENV<ZOE_VOTEBAN_REACTION_AGAINST_EMOTE> || "❎";
my Int $votes-required = %*ENV<ZOE_VOTEBAN_VOTES_REQUIRED> || 1;
my Int $voting-timeout = %*ENV<ZOE_VOTEBAN_VOTING_TIMEOUT> || 10;

my PERMISSION @protected-permissions = %*ENV<ZOE_VOTEBAN_PROTECTED_PERMISSIONS> || KICK_MEMBERS, BAN_MEMBERS, ADMINISTRATOR, MANAGE_GUILD;
my @protected-roles = %*ENV<ZOE_VOTEBAN_PROTECTED_ROLES> || 733655449987055697;

my Bool $vote-in-progress = False;

sub MAIN($token) {
    my $discord = API::Discord.new(:$token);

    $discord.connect;
    await $discord.ready;

    react {
        whenever $discord.messages -> $message {
            my ($command, $arg) = $message.content.split(/ \s+ /);
            my $guild = $message.channel.guild;

            if $command eq $command-prefix ~ 'voteban' {
                if not $vote-in-progress {
                    if $arg and $arg ~~ / '<@' '!'? <(\d+)> '>' / {
                        my $user-id = $/.Int;
                        my $user = $discord.get-user($user-id);
                        my $member = $guild.get-member($user);

                        if not ($member.has-any-permission(@protected-permissions)|| $user.is-bot) {
                            whenever start-vote(:$discord, :$message, :$user, :$member) -> %result {
                                %result.say;
                                whenever end-vote(:$discord, :$guild, :$user, :$message, :%result) {
                                    # Nothing - this is here so we learn about
                                    # errors
                                }
                            }
                        } else {
                            my $exception = "This user is immune to votebans.";
                            my %response = exception(:$exception);
                            $message.channel.send-message(|%response)
                        }
                    } else {
                        my $exception = "No valid user was found.";
                        my %response = exception(:$exception);
                        $message.channel.send-message(|%response)
                    }
                } elsif $vote-in-progress {
                    my $exception = "There is already a voteban in progress.";
                    my %response = exception(:$exception);
                    $message.channel.send-message(|%response)
                }
            }
        }
    }
}

sub start-vote(:$discord, :$message, :$user, :$member) {
    $vote-in-progress = True;

    my %payload = description => "React using an appropriate emoji in order to cast your vote. At least $votes-required positive votes must be made within $voting-timeout seconds for the ban to be approved. Negative votes reduce the counter and increase the number of votes required.",
            fields => [
                { inline => True, name => "$reaction-for-emote", value => 'Approve voteban'},
                { inline => True, name => "$reaction-against-emote", value => 'Reject voteban' }
            ],
            author => { name => "Voteban started for {$user.username}#{$user.discriminator}", icon_url => "https://cdn.discordapp.com/avatars/{$user.id}/{$user.avatar-hash}.png" }
    ;

    my $poll = await $message.channel.send-message(embed => %payload).then(-> $p {
        my $m = $p.result;
        await $m.add-reaction($reaction-for-emote);
        sleep(1/2);
        await $m.add-reaction($reaction-against-emote);

        $m;
    });

    Promise(supply {
        my Int $yes-votes = 0;
        my Int $no-votes = 0;

        whenever $poll.events -> $event {
            if $event<t> eq 'MESSAGE_REACTION_ADD' {
                $yes-votes++ if $event<d><emoji><name> eq $reaction-for-emote;
                $no-votes++ if $event<d><emoji><name> eq $reaction-against-emote;
            }
            elsif $event<t> eq 'MESSAGE_REACTION_REMOVE' {
                $yes-votes-- if $event<d><emoji><name> eq $reaction-for-emote;
                $no-votes-- if $event<d><emoji><name> eq $reaction-against-emote;
            }
        }

        whenever Promise.in($voting-timeout) {
            emit( { yes => $yes-votes, no => $no-votes } );
            done
        }
    })
}

sub end-vote(:$discord, :$guild, :$user, :$message, :%result) {
    my Int $total = %result<yes> - %result<no>;

    if $total >= $votes-required {
        my %payload = description => "$total votes out of a required $votes-required were achieved.",
                fields => [
                    { inline => True, name => "$reaction-for-emote", value => "{%result<yes>}"},
                    { inline => True, name => "$reaction-against-emote", value => "{%result<no>}" }
                ],
                author => { name => "{$user.username}#{$user.discriminator} was banned", icon_url => "https://cdn.discordapp.com/avatars/{$user.id}/{$user.avatar-hash}.png" }
        ;
        $guild.create-ban($user.id);
        $message.channel.send-message(embed => %payload);
    } else {
        my %payload = description => "$total votes out of a required $votes-required were achieved.",
                fields => [
                    { inline => True, name => "$reaction-for-emote", value => "{%result<yes>}"},
                    { inline => True, name => "$reaction-against-emote", value => "{%result<no>}" }
                ],
                author => { name => "{$user.username}#{$user.discriminator} was not banned", icon_url => "https://cdn.discordapp.com/avatars/{$user.id}/{$user.avatar-hash}.png" }
        ;
        $message.channel.send-message(embed => %payload);
    }

    $vote-in-progress = False;
}

sub exception(:$exception) {
    my %payload = title => 'Something went wrong!',
            description => "$exception";

    return embed => %payload;
}
