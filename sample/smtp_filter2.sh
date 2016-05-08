#! /bin/ash
#
# This part of smtp_wrapper is distributed under GNU General Public License.
#
# Sample spam filter script
#   by "Masahiko Ito" <m-ito@myh.no-ip.org>
#
# Thanks to http://www.gabacho-net.jp/anti-spam/anti-spam-system.html
#
# コンテンツに対するチェック(第三者リレー)を行う場合のスクリプト。`-f'オプションに指定する。
#
#============================================================
#
# 割り込み時の処理設定
#
trap "spam_exit 1 \"kill by signal\"" INT HUP TERM QUIT
#============================================================
#
# 実行パス設定
#
PATH="/usr/local/smtp_wrapper:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
export PATH
#============================================================
#
# timeout (This was bad idea :<)
#
#timeout=10m
#(sleep ${timeout}; kill -15 ${PPID}) &
#============================================================
#
# smtp_wrapperディレクトリ指定
#
smtp_wrapper_dir="/usr/local/smtp_wrapper"
#
# テンポラリスプールディレクトリ
tmp="/var/tmp"
#
# syslog出力時のID
sl_ident="smtp_filter2"
#
# 全てのリレーを許可するホストのIPデータベース
relay_allow_host="${smtp_wrapper_dir}/relay_allow_host_db"
# 外部のサーバに許可する配送先アドレスデータベース
relay_allow_address="${smtp_wrapper_dir}/relay_allow_address_db"
#============================================================
#
# ある種の定数
#
cr=`echo -n -e '\r'`; export cr
tab=`echo -n -e '\t'`; export tab
pid="$$"; export pid
#============================================================
#
# spamと判断時に終了させる処理
#
spam_exit ()
{
    if [ -r ${tmp}/smtp_filter2.*.$$.tmp ]
    then
        logger -p mail.info -t ${sl_ident} "[$$]:`head -50 ${tmp}/smtp_filter2.*.$$.tmp | egrep -i '^MAIL *FROM:|^RCPT *TO:|^From:|^To:|^Subject:|^Date:'`"
    else
        logger -p mail.info -t ${sl_ident} "[$$]:`head -50 | egrep -i '^MAIL *FROM:|^RCPT *TO:|^From:|^To:|^Subject:|^Date:'`"
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
# 第三者リレーチェック処理
#
relay_check ()
{
	allow_ip=""
	for i in `grep -v '^#' ${relay_allow_host}`
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
		for i in `awk 'BEGIN{
				cr = ENVIRON["cr"]
			}
			{
				if (length($0) == 1 && index($0, cr) > 0){
					exit;
				}else{
					print;
				}
			}' ${tmp}/smtp_filter2.1.$$.tmp |\
			egrep -i '^RCPT *TO:' |\
			sed -e 's/ *//g`
		do
			for j in `grep -v '^#' ${relay_allow_address}`
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
				spam_exit 12 "no relay" # *** 第三者中継拒否 ***
			fi
		done
	fi
}
#============================================================
#
# 主処理開始
#
from_ip=""
from_hostname=""
#
#============================================================
#
# メール本文を全文受信(スプール)する
#
cat >${tmp}/smtp_filter2.1.$$.tmp
#============================================================
#
# 第三者中継拒否
#
from_ip=${SW_FROM_IP}
from_hostname=`host ${from_ip} 2>/dev/null |\
	egrep 'domain name pointer' |\
	head -1 |\
	sed -e 's/^.* domain name pointer *//;s/\.$//'`
#
relay_check
#
#============================================================
#
# 正当なメールと判断されたものを出力する
#
export from_ip
export from_hostname
#
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
}' ${tmp}/smtp_filter2.1.$$.tmp
#
#============================================================
#
# 後始末して終了
#
rm -f ${tmp}/smtp_filter2.*.$$.tmp
exit 0
