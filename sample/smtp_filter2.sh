#! /bin/ash
#
# This part of smtp_wrapper is distributed under GNU General Public License.
#
# Sample spam filter script
#   by "Masahiko Ito" <m-ito@myh.no-ip.org>
#
# Thanks to http://www.gabacho-net.jp/anti-spam/anti-spam-system.html
#
# ����ƥ�Ĥ��Ф�������å�(�軰�ԥ�졼)��Ԥ����Υ�����ץȡ�`-f'���ץ����˻��ꤹ�롣
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
sl_ident="smtp_filter2"
#
# ���ƤΥ�졼����Ĥ���ۥ��Ȥ�IP�ǡ����١���
relay_allow_host="${smtp_wrapper_dir}/relay_allow_host_db"
# �����Υ����Ф˵��Ĥ��������襢�ɥ쥹�ǡ����١���
relay_allow_address="${smtp_wrapper_dir}/relay_allow_address_db"
#============================================================
#
# ���������
#
cr=`echo -n -e '\r'`; export cr
tab=`echo -n -e '\t'`; export tab
pid="$$"; export pid
#============================================================
#
# spam��Ƚ�ǻ��˽�λ���������
#
spam_exit ()
{
    if [ -r ${tmp}/smtp_filter2.*.$$.tmp ]
    then
        logger -p mail.info -t ${sl_ident} "[$$]:`cat ${tmp}/smtp_filter2.*.$$.tmp | head -50 | egrep -i '^MAIL *FROM:|^RCPT *TO:|^From:|^To:|^Subject:|^Date:'`"
    else
        logger -p mail.info -t ${sl_ident} "[$$]:`cat | head -50 | egrep -i '^MAIL *FROM:|^RCPT *TO:|^From:|^To:|^Subject:|^Date:'`"
    fi
    logger -p mail.info -t ${sl_ident} "[$$]:IP=${from_ip}"
    logger -p mail.info -t ${sl_ident} "[$$]:HOST=${from_hostname}"
    logger -p mail.info -t ${sl_ident} "[$$]:EXIT=$1"
    logger -p mail.info -t ${sl_ident} "[$$]:REASON=$2"
    rm -f ${tmp}/smtp_filter2.*.$$.tmp
    echo "[$$]:IP=${from_ip} HOST=${from_hostname} EXIT=$1 REASON=$2"
    exit $1
}
#============================================================
#
# �軰�ԥ�졼�����å�����
#
relay_check ()
{
	allow_ip=""
	for i in `cat ${relay_allow_host} |\
		grep -v '^#' |\
		sed -e "s/${tab}/ /g;s/  */ /g" |\
		cut -d ' ' -f 1`
	do
		allow_ip=`echo ${from_ip} |\
			egrep "$i"`
		if [ "X${allow_ip}" != "X" ]
		then
			break
		fi
	done
#
	if [ "X${allow_ip}" = "X" ]
	then
		for i in `cat ${tmp}/smtp_filter2.1.$$.tmp |\
			awk 'BEGIN{
				cr = ENVIRON["cr"]
			}
			{
				if (length($0) == 1 && index($0, cr) > 0){
					exit;
				}else{
					print;
				}
			}' |\
			egrep -i '^RCPT *TO:' |\
			sed -e 's/ *//g`
		do
			for j in `cat ${relay_allow_address} |\
				grep -v '^#'`
			do
				allow_rcpt=""
				allow_rcpt=`echo $i |\
					egrep "$j"`
				if [ "X${allow_rcpt}" != "X" ]
				then
					break;
				fi
			done
			if [ "X${allow_rcpt}" = "X" ]
			then
				spam_exit 12 "no relay" # *** �軰����ѵ��� ***
			fi
		done
	fi
}
#============================================================
#
# ���������
#
from_ip=""
from_hostname=""
#
#============================================================
#
# �᡼����ʸ����ʸ����(���ס���)����
#
cat >${tmp}/smtp_filter2.1.$$.tmp
#============================================================
#
# �軰����ѵ���
#
from_ip=${SW_FROM_IP}
from_hostname=`host ${from_ip} 2>/dev/null |\
	egrep -i 'domain name pointer' |\
	head -1 |\
	sed -e 's/^.* domain name pointer *//;s/\.$//'`
#
relay_check
#
#============================================================
#
# �����ʥ᡼���Ƚ�Ǥ��줿��Τ���Ϥ���
#
export from_ip
export from_hostname
#
cat ${tmp}/smtp_filter2.1.$$.tmp |\
awk 'BEGIN{
    from_ip = ENVIRON["from_ip"]
    from_hostname = ENVIRON["from_hostname"]
    pid = ENVIRON["pid"]
    out_sw = 0;
}
{
    if (out_sw == 0){
        head = toupper($0);
        if (head ~ /^DATA\r$/ ||
            head ~ /^DATA$/){
            out_sw = 1;
        }
    }

    if (out_sw == 1){
        print $0;
    }
}
END{
    if (out_sw == 0){
        printf("[%d]:IP=%-s HOST=%-s REASON=NOT spam, but NO DATA\n", pid, from_ip, from_hostname)
    }
}'
#
#============================================================
#
# ��������ƽ�λ
#
rm -f ${tmp}/smtp_filter2.*.$$.tmp
exit 0
