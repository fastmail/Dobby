# Dobby: a DigitalOcean client

It's a half-baked client for the DigitalOcean API, made to do only and exactly
what we need for box management.  More interesting is Boxmate:

# Boxmate: your FM VM BFF

Boxmate, or `box` to his friends, is a little command for managing Fastmail
VMs.  Mostly Fastmail-in-a-Box, but others, too.

To learn more, you should just run `box commands` and `box help ${command}` to
see up-to-date information.  We don't want the README to get woefully out of
date, right?

Basically, though, the `box` command will let you create, destroy, list, and
ssh to VMs.  More features may come later.

## Installing Boxmate

### Rik recommends hardcore mode:

1. clone Dobby
2. install them, in that order, "the usual Perl way", by running
   `cpanm --installdeps . && perl Makefile.PL && make install`
3. run `box`

For even better value, get your token securely from 1Password by setting your
`DIGITALOCAEN_TOKEN` environment variable to an `opcli` URI like this:

```
DIGITALOCEAN_TOKEN=opcli:a=fm:v=Employee:i=xyzzy:f=credential
```

(For more information on that see [his blog
post](https://rjbs.cloud/blog/2024/08/onepassword-library-tweaks/).)

Of course, not everybody likes dealing with all those dependencies, especially
when you start getting prompted for LibXML.

### Easy mode:

There's a `docker/Dockerfile` in this repo.  A container built with this
Dockerfile will have `box` ready to go in its path.  Probably this could be
made much slicker, but for now, it should work okay.

## Configuring Boxmate

You need two things:

1. a `DIGITALOCEAN_TOKEN` environment variable, preferably with an `opcli`
   entry, but potentially with token
2. a valid `~/.boxmate.toml`

The TOML file will look like this:

```toml
[create]
ssh_key_id = "id_ed25519"
digitalocean_ssh_key_name = "whatever"
```

The DigitalOcean key name is used to find the SSH key in DO that will be
installed as a login key on the box.  Generally, this is your unix username.

The `ssh_key_id` is your local ssh key id that will be used to authenticate
with boxes to run setup.
