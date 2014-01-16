package Ukigumo::Agent::Dispatcher;
use strict;
use warnings;
use utf8;

use Amon2::Web::Dispatcher::RouterBoom;
use Ukigumo::Agent::Manager;
use Data::Validator;
use JSON;
use Log::Minimal;

get '/' => sub {
    my $c = shift;

    $c->render(
        'index.tt' => {
            children     => $c->manager->children,
            job_queue    => $c->manager->job_queue,
            server_url   => $c->manager->server_url,
            work_dir     => $c->manager->work_dir,
            max_children => $c->manager->max_children,
        }
    );
};

my $rule = Data::Validator->new(
    repository => { isa => 'Str' },
    branch     => { isa => 'Str' },
)->with('NoThrow');
post '/api/v0/enqueue' => sub {
    my $c = shift;

    my $args = $rule->validate(+{%{$c->req->parameters}});
    if ($rule->has_errors) {
        my $errors = $rule->clear_errors();

        my $res = $c->render_json({errors => $errors});
        $res->code(400);
        return $res;
    }

    $c->manager->register_job($args);

    return $c->render_json(+{});
};

post '/api/github_hook' => sub {
    my $c = shift;

    my $payload = from_json $c->req->param('payload');
    my $args;
    eval {
        # TODO How to pass commit id?
        # my @commits = @{$payload->{commits}};
        #   ...
        # commit => $commits[$#commits]->{id},
        my $repo_url = $payload->{repository}->{url};
        if ($ENV{UKIGUMO_AGENT_GITHUB_HOOK_FORCE_GIT_URL}) {
            # From: https://github.com/tokuhirom/plenv.git
            # To: git@github.com:tokuhirom/plenv.git
            $repo_url =~ s!\Ahttps?://([^/]+)/!git\@$1:!;
        }
        $args = +{
            repository => $repo_url,
            branch => $payload->{repository}->{master_branch},
        };
    };
    if (my $e = $@) {
        warnf("An error occured: %s", $e);
        my $res = $c->render_json({errors => $e});
        $res->code(400);
        return $res;
    }

    $c->manager->register_job($args);

    return $c->render_json(+{});
};

1;
