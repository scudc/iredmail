# --------------------------------------------
# Amavisd-new.
# --------------------------------------------

amavisd_dkim()
{
    pem_file="${AMAVISD_DKIM_DIR}/${FIRST_DOMAIN}.pem"

    ECHO_INFO "Create directory to store CA files: ${AMAVISD_DKIM_DIR}." 
    mkdir -p ${AMAVISD_DKIM_DIR} 2>/dev/null && \
    chown amavis:amavis ${AMAVISD_DKIM_DIR}

    ECHO_INFO "Generate CA files: ${pem_file}." 
    amavisd genrsa ${pem_file} >/dev/null 2>&1 && \
    setfacl -m u:amavis:r-- ${pem_file}

    cat >> ${AMAVISD_CONF} <<EOF
# Add dkim_key here.
dkim_key("${FIRST_DOMAIN}", "${AMAVISD_DKIM_SELECTOR}", "${pem_file}");

# Note that signing mail for subdomains with a key of a parent
# domain is treated by recipients as a third-party key, which
# may 'hold less merit' in their eyes. If one has a choice,
# it is better to publish a key for each domain (e.g. host1.a.cn)
# if mail is really coming from it. Sharing a pem file
# for multiple domains may be acceptable, so you don't need
# to generate a different key for each subdomain, but you
# do need to publish it in each subdomain. It is probably
# easier to avoid sending addresses like host1.a.cn and
# always use a parent domain (a.cn) in 'From:', thus
# avoiding the issue altogether.
#dkim_key("host1.${FIRST_DOMAIN}", "${AMAVISD_DKIM_SELECTOR}", "${pem_file}");
#dkim_key("host3.${FIRST_DOMAIN}", "${AMAVISD_DKIM_SELECTOR}", "${pem_file}");

# Add new dkim_key for other domain.
#dkim_key('Your_New_Domain_Name', 'dkim', 'Your_New_Pem_File');

@dkim_signature_options_bysender_maps = ( {
    # ------------------------------------
    # For domain: ${FIRST_DOMAIN}.
    # ------------------------------------
    # 'd' defaults to a domain of an author/sender address,
    # 's' defaults to whatever selector is offered by a matching key 

    '${FIRST_DOMAIN_ADMIN_NAME}@${FIRST_DOMAIN}'    => { d => "${FIRST_DOMAIN}", a => 'rsa-sha256', ttl =>  7*24*3600 },
    #"spam-reporter@${FIRST_DOMAIN}"    => { d => "${FIRST_DOMAIN}", a => 'rsa-sha256', ttl =>  7*24*3600 },

    # explicit 'd' forces a third-party signature on foreign (hosted) domains
    "${FIRST_DOMAIN}"  => { d => "${FIRST_DOMAIN}", a => 'rsa-sha256', ttl => 10*24*3600 },
    #"host1.${FIRST_DOMAIN}"  => { d => "host1.${FIRST_DOMAIN}", a => 'rsa-sha256', ttl => 10*24*3600 },
    #"host2.${FIRST_DOMAIN}"  => { d => "host2.${FIRST_DOMAIN}", a => 'rsa-sha256', ttl => 10*24*3600 },
    # ---- End domain: ${FIRST_DOMAIN} ----

    # catchall defaults
    '.' => { a => 'rsa-sha256', c => 'relaxed/simple', ttl => 30*24*3600 },
} );
EOF

    cat >> ${TIP_FILE} <<EOF
DNS record for DKIM support:
$(amavisd showkeys)

EOF

    echo 'export status_amavisd_dkim="DONE"' >> ${STATUS_FILE}
}

amavisd_config()
{
    backup_file ${AMAVISD_CONF}

    ECHO_INFO "Configure amavisd-new: ${AMAVISD_CONF}."

    #perl -pi -e 's/^(\$max_servers)/$1\ =\ 15\;\t#/' ${AMAVISD_CONF}
    # ---- Use amavisd daemon user. ----
    #perl -pi -e 's/^(\$daemon_user)/$1\ =\ "clamav"\;\t#/' ${AMAVISD_CONF}
    #perl -pi -e 's/^(\$daemon_group)/$1\ =\ "clamav"\;\t#/' ${AMAVISD_CONF}

    # ---- Make amavisd log to standalone file: ${AMAVISD_LOGROTATE_FILE} ----
    perl -pi -e 's#(.*syslog_facility.*)(mail)(.*)#${1}local0${3}#' ${AMAVISD_CONF}
    echo -e "local0.*\t\t\t\t\t\t-${AMAVISD_LOGFILE}" >>/etc/syslog.conf

    perl -pi -e 's/^(\$mydomain)/$1\ =\ \"$ENV{'HOSTNAME'}\"\;\t#/' ${AMAVISD_CONF}
    perl -pi -e 's/(.*local_domains_maps.*)(].*)/${1},"$ENV{'FIRST_DOMAIN'}"${2}/' ${AMAVISD_CONF}

    # Set default score.
    #perl -pi -e 's/(.*)(sa_tag_level_deflt)(.*)/${1}${2} = 4.0; #${3}/' ${AMAVISD_CONF}
    #perl -pi -e 's/(.*)(sa_tag2_level_deflt)(.*)/${1}${2} = 6; #${3}/' ${AMAVISD_CONF}
    #perl -pi -e 's/(.*)(sa_kill_level_deflt)(.*)/${1}${2} = 10; #${3}/' ${AMAVISD_CONF}

    # Set admin address.
    perl -pi -e 's#(virus_admin.*= ")(virusalert)(.*)#${1}root${3}#' ${AMAVISD_CONF}
    perl -pi -e 's#(mailfrom_notify_admin.*= ")(virusalert)(.*)#${1}root${3}#' ${AMAVISD_CONF}
    perl -pi -e 's#(mailfrom_notify_recip.*= ")(virusalert)(.*)#${1}root${3}#' ${AMAVISD_CONF}
    perl -pi -e 's#(mailfrom_notify_spamadmin.*= ")(spam.police)(.*)#${1}root${3}#' ${AMAVISD_CONF}

    # Remove the content from '@av_scanners' to the end of file.
    new_conf="$(sed '/\@av_scanners/,$d' ${AMAVISD_CONF})"

    # Generate new configration file(Part).
    echo -e "${new_conf}" > ${AMAVISD_CONF}

    # Set pid_file.
    #echo '$pid_file = "/var/run/clamav/amavisd.pid";' >> ${AMAVISD_CONF}

    # Enable DKIM feature.
    if [ X"${ENABLE_DKIM}" == X"YES" ]; then
        [ X"${status_amavisd_dkim}" != X"DONE" ] && amavisd_dkim
    else
        :
    fi

    cat >> ${AMAVISD_CONF} <<EOF

# Set listen IP/PORT.
\$notify_method  = 'smtp:[127.0.0.1]:10025';
\$forward_method = 'smtp:[127.0.0.1]:10025';

# Set default action.
\$final_virus_destiny      = D_DISCARD;
\$final_banned_destiny     = D_PASS;
\$final_spam_destiny       = D_PASS;
\$final_bad_header_destiny = D_PASS;

@av_scanners = (

    #### http://www.clamav.net/
    ['ClamAV-clamd',
    \&ask_daemon, ["CONTSCAN {}\n", "/tmp/clamd.socket"],
    qr/\bOK$/, qr/\bFOUND$/,
    qr/^.*?: (?!Infected Archive)(.*) FOUND$/ ],
);

@av_scanners_backup = (

    ### http://www.clamav.net/   - backs up clamd or Mail::ClamAV
    ['ClamAV-clamscan', 'clamscan',
    "--stdout --disable-summary -r --tempdir=$TEMPBASE {}", [0], [1],
    qr/^.*?: (?!Infected Archive)(.*) FOUND$/ ],
);

# SpamAssassin debugging. Default if off(0).
# Note: '\$log_level' variable above is required for SA debug.
\$sa_debug = 0;

# Modify email subject, add '$sa_spam_subject_tag'.
#   0:  disable
#   1:  enable
\$sa_spam_modifies_subj = 1;

# remove existing headers
#\$remove_existing_x_scanned_headers= 0;
#\$remove_existing_spam_headers = 0;

# Leave empty (undef) to add no header.
# Modify /usr/sbin/amavisd file to add customize header in:
#
#   sub add_forwarding_header_edits_per_recip
#
#\$X_HEADER_TAG = 'X-Virus-Scanned';
#\$X_HEADER_LINE = "by amavisd at \$myhostname";

1;  # insure a defined return
EOF
    # ------------- END configure /etc/amavisd.conf ------------

    # Configure postfix: master.cf.
    cat >> ${POSTFIX_FILE_MASTER_CF} <<EOF
smtp-amavis unix -  -   -   -   2  smtp
    -o smtp_data_done_timeout=1200
    -o smtp_send_xforward_command=yes
    -o disable_dns_lookups=yes
    -o max_use=20

127.0.0.1:10025 inet n  -   -   -   -  smtpd
    -o content_filter=
    -o local_recipient_maps=
    -o relay_recipient_maps=
    -o smtpd_restriction_classes=
    -o smtpd_delay_reject=no
    -o smtpd_client_restrictions=permit_mynetworks,reject
    -o smtpd_helo_restrictions=
    -o smtpd_sender_restrictions=
    -o smtpd_recipient_restrictions=permit_mynetworks,reject
    -o mynetworks_style=host
    -o mynetworks=127.0.0.0/8
    -o strict_rfc821_envelopes=yes
    -o smtpd_error_sleep_time=0
    -o smtpd_soft_error_limit=1001
    -o smtpd_hard_error_limit=1000
    -o smtpd_client_connection_count_limit=0
    -o smtpd_client_connection_rate_limit=0
    -o receive_override_options=no_header_body_checks,no_unknown_recipient_checks
EOF

    postconf -e content_filter='smtp-amavis:[127.0.0.1]:10024'

    ECHO_INFO "Setting logrotate for amavisd log file: ${AMAVISD_LOGFILE}."
    cat > ${AMAVISD_LOGROTATE_FILE} <<EOF
${CONF_MSG}
${AMAVISD_LOGFILE} {
    compress
    weekly
    rotate 10
    create 0600 amavis amavis
    missingok
    postrotate
        /sbin/killall -HUP syslogd
    endscript
}
EOF

    cat >> ${TIP_FILE} <<EOF
Amavisd-new:
    * Configuration files:
        - /etc/amavisd.conf
        - ${POSTFIX_FILE_MASTER_CF}
        - ${POSTFIX_FILE_MAIN_CF}
    * RC script:
        - /etc/init.d/amavisd

EOF

    echo 'export status_amavisd_config="DONE"' >> ${STATUS_FILE}
}