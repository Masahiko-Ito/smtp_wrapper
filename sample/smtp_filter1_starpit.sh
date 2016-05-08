#! /bin/ash
#
# This part of smtp_wrapper is distributed under GNU General Public License.
#
# Sample spam filter script
#   by "Masahiko Ito" <m-ito@myh.no-ip.org>
#
# Thanks to http://www.gabacho-net.jp/anti-spam/anti-spam-system.html
#           http://d.hatena.ne.jp/stealthinu/20060706/p5
#
# IP���Ф�������å�(S25R+tarpitting)��Ԥ����Υ�����ץȡ�`-if'���ץ����˻��ꤹ�롣
#
#============================================================
#
# �����߻��ν�������
#
trap "spam_exit 1 \"kill by signal\"" INT HUP TERM QUIT
#============================================================
#
# �¹ԥѥ�����
#
PATH="/usr/local/smtp_wrapper:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
export PATH
#============================================================
#
# smtp_wrapper�ǥ��쥯�ȥ����
#
smtp_wrapper_dir="/usr/local/smtp_wrapper"
#
# �ƥ�ݥ�ꥹ�ס���ǥ��쥯�ȥ�
tmp="/var/tmp"
#
# syslog���ϻ���ID
sl_ident="smtp_filter1_starpit"
#
# �����ۥ��Ȥ�IP�ǡ����١���
white_ip_db="${smtp_wrapper_dir}/white_ip_db"
# �����ۥ��Ȥ�FQDN�ǡ����١���
white_hostname_db="${smtp_wrapper_dir}/white_hostname_db"
# �����ۥ��Ȥ�IP�ǡ����١���
black_ip_db="${smtp_wrapper_dir}/black_ip_db"
# �����ۥ��Ȥ�FQDN�ǡ����١���
black_hostname_db="${smtp_wrapper_dir}/black_hostname_db"
#
#============================================================
#
# ���������
#
cr=`echo -n -e '\r'`; export cr
tab=`echo -n -e '\t'`; export tab
pid="$$"; export pid
#============================================================
#
# S25R�ˤҤä�����MTA���Ф����ٱ����
#
delay="60s"
#============================================================
#
# spam��Ƚ�ǻ��˽�λ���������
#
spam_exit ()
{
    logger -p mail.info -t ${sl_ident} "[$$]:IP=${from_ip}"
    logger -p mail.info -t ${sl_ident} "[$$]:HOST=${from_hostname}"
    logger -p mail.info -t ${sl_ident} "[$$]:EXIT=$1"
    logger -p mail.info -t ${sl_ident} "[$$]:REASON=$2"
    sleep ${delay}
    rm -f ${tmp}/smtp_filter1_starpit.*.$$.tmp
    exit $1
}
#============================================================
#
# ���ѥ�����å�����
#
spam_check ()
{
    if [ "X${from_ip}" = "X" ]
    then
        spam_exit 2 "unknown ip" # *** �����ۥ��Ȥ�IP��Ƚ��ʤ� ***
    fi
#
    for i in `egrep -v '^#' ${black_ip_db}`
    do
        black_ip=`echo "${from_ip}" |\
    	egrep "$i"`
        if [ "X${black_ip}" != "X" ]
        then
            spam_exit 3 "black IP" # *** �����ۥ���IP����IP�ǡ����١�������Ͽ����Ƥ��� ***
        fi
    done
#
    for i in `egrep -v '^#' ${white_ip_db}`
    do
        white_ip=`echo "${from_ip}" |\
    	egrep "$i"`
        if [ "X${white_ip}" != "X" ]
        then
            break;
        fi
    done
#
    from_hostname=`host ${from_ip} 2>/dev/null |\
    	egrep 'domain name pointer' |\
    	head -1 |\
    	sed -e 's/^.* domain name pointer *//;s/\.$//'`
    if [ "X${white_ip}" = "X" -a "X${from_hostname}" = "X" ]
    then
        spam_exit 4 "no dns" # *** �����ۥ��Ȥ�IP���հ����Ǥ��ʤ� ***
    fi
#
    for i in `egrep -v '^#' ${black_hostname_db}`
    do
        black_hostname=`echo "${from_hostname}" |\
    	egrep "$i"`
        if [ "X${black_hostname}" != "X" ]
        then
            spam_exit 5 "black hostname" # *** �����ۥ���̾�����ۥ���̾�ǡ����١�������Ͽ����Ƥ��� ***
        fi
    done
#
    for i in `egrep -v '^#' ${white_hostname_db}`
    do
        white_hostname=`echo "${from_hostname}" |\
    	egrep "$i"`
        if [ "X${white_hostname}" != "X" ]
        then
            break;
        fi
    done
#
    if [ "X${white_ip}" = "X" -a "X${white_hostname}" = "X" ]
    then
#
        spam_host=`echo ${from_hostname} |\
        	egrep '^[^\.]*[0-9][^0-9\.]+[0-9]'`
        if [ "X${spam_host}" != "X" ]
        then
            spam_exit 6 "rule 1" # *** �Υ롼��1�ϡ��հ���FQDN�κǲ��̡ʺ�ü�ˤ�̾�����������ʳ���ʸ�����ʬ�Ǥ��줿��İʾ�ο� ***
        fi
#
        spam_host=`echo ${from_hostname} |\
        	egrep '^[^\.]*[0-9]{5}'`
        if [ "X${spam_host}" != "X" ]
        then
            spam_exit 7 "rule 2" # *** �Υ롼��2�ϡ��հ���FQDN�κǲ��̤�̾������5�İʾ�Ϣ³���������ޤ� ***
        fi
#
        spam_host=`echo ${from_hostname} |\
        	egrep '^([^\.]+\.)?[0-9][^\.]*\.[^\.]+\..+\.[a-z]'`
        if [ "X${spam_host}" != "X" ]
        then
            spam_exit 8 "rule 3" # *** �Υ롼��3�ϡ��հ���FQDN�ξ��3���ؤ�������ǲ��̤ޤ��ϲ��̤���2���ܤ�̾���������ǻϤޤ� ***
        fi
#
        spam_host=`echo ${from_hostname} |\
        	egrep '^[^\.]*[0-9]\.[^\.]*[0-9]-[0-9]'`
        if [ "X${spam_host}" != "X" ]
        then
            spam_exit 9 "rule 4" # *** �Υ롼��4�ϡ��հ���FQDN�κǲ��̤�̾���������ǽ���ꡢ���Ĳ��̤���2���ܤ�̾������1�ĤΥϥ��ե��ʬ�Ǥ��줿��İʾ�ο������ޤ� ***
        fi
#
        spam_host=`echo ${from_hostname} |\
        	egrep '^[^\.]*[0-9]\.[^\.]*[0-9]\.[^\.]+\..+\.'`
        if [ "X${spam_host}" != "X" ]
        then
            spam_exit 10 "rule 5" # *** �Υ롼��5�ϡ��հ���FQDN��5���ذʾ�ǡ�����2���ؤ�̾�����Ȥ�˿����ǽ���� ***
        fi
#
        spam_host=`echo ${from_hostname} |\
        	egrep '^(dhcp|dialup|ppp|adsl)[^\.]*[0-9]'`
        if [ "X${spam_host}" != "X" ]
        then
            spam_exit 11 "rule 6" # *** �Υ롼��6�ϡ��հ���FQDN�κǲ��̤�̾������dhcp�ס���dialup�ס���ppp�ס��ޤ��ϡ�adsl�פǻϤޤꡢ���Ŀ�����ޤ� ***
        fi
    fi
}
#============================================================
#
# ���������
#
from_ip=""
from_hostname=""
white_ip=""
white_hostname=""
black_ip=""
black_hostname=""
#
#============================================================
#
# ľ��SMTP��³ʬ�Υ����å�
#
# (smtp_wrapper ����Ķ��ѿ� SW_FROM_IP ����³��IP���Ϥ����)
#
from_ip=${SW_FROM_IP}
#
spam_check
#============================================================
#
# ��������ƽ�λ
#
rm -f ${tmp}/smtp_filter1_starpit.*.$$.tmp
exit 0
