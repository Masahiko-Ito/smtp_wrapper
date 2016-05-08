#! /bin/ash
#
# This part of smtp_wrapper is distributed under GNU General Public License.
#
# Sample spam filter script
#   by "Masahiko Ito" <m-ito@myh.no-ip.org>
#
# Thanks to http://www.gabacho-net.jp/anti-spam/anti-spam-system.html
#
# IPに対するチェック(S25R)とコンテンツに対するチェック(第三者リレー)を同時に
# 行う場合のスクリプト。`-f'オプションに指定する。`-if'オプションは指定しない。
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
sl_ident="smtp_filter"
#
# 正当ホストのIPデータベース
white_ip_db="${smtp_wrapper_dir}/white_ip_db"
# 正当ホストのFQDNデータベース
white_hostname_db="${smtp_wrapper_dir}/white_hostname_db"
# 不正ホストのIPデータベース
black_ip_db="${smtp_wrapper_dir}/black_ip_db"
# 不正ホストのFQDNデータベース
black_hostname_db="${smtp_wrapper_dir}/black_hostname_db"
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
    if [ -r ${tmp}/smtp_filter.*.$$.tmp ]
    then
        logger -p mail.info -t ${sl_ident} "[$$]:`head -50 ${tmp}/smtp_filter.*.$$.tmp | egrep -i '^MAIL *FROM:|^RCPT *TO:|^From:|^To:|^Subject:|^Date:'`"
    else
        logger -p mail.info -t ${sl_ident} "[$$]:`head -50 | egrep -i '^MAIL *FROM:|^RCPT *TO:|^From:|^To:|^Subject:|^Date:'`"
    fi
    logger -p mail.info -t ${sl_ident} "[$$]:IP=${from_ip}"
    logger -p mail.info -t ${sl_ident} "[$$]:HOST=${from_hostname}"
    logger -p mail.info -t ${sl_ident} "[$$]:EXIT=$1"
    logger -p mail.info -t ${sl_ident} "[$$]:REASON=$2"
    rm -f ${tmp}/smtp_filter.*.$$.tmp
    echo "[$$]:IP=${from_ip} HOST=${from_hostname} EXIT=$1 REASON=$2"
    exit $1
}
#============================================================
#
# スパムチェック処理
#
spam_check ()
{
    if [ "X${from_ip}" = "X" ]
    then
        spam_exit 2 "unknown ip" # *** 送信ホストのIPが判らない ***
    fi
#
    for i in `egrep -v '^#' ${black_ip_db}`
    do
        black_ip=`echo "${from_ip}" |\
    	egrep "$i"`
        if [ "X${black_ip}" != "X" ]
        then
            spam_exit 3 "black IP" # *** 送信ホストIPが黒IPデータベースに登録されている ***
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
        spam_exit 4 "no dns" # *** 送信ホストのIPが逆引きできない ***
    fi
#
    for i in `egrep -v '^#' ${black_hostname_db}`
    do
        black_hostname=`echo "${from_hostname}" |\
    	egrep "$i"`
        if [ "X${black_hostname}" != "X" ]
        then
            spam_exit 5 "black hostname" # *** 送信ホスト名が黒ホスト名データベースに登録されている ***
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
            spam_exit 6 "rule 1" # *** ［ルール1］　逆引きFQDNの最下位（左端）の名前が、数字以外の文字列で分断された二つ以上の数 ***
        fi
#
        spam_host=`echo ${from_hostname} |\
        	egrep '^[^\.]*[0-9]{5}'`
        if [ "X${spam_host}" != "X" ]
        then
            spam_exit 7 "rule 2" # *** ［ルール2］　逆引きFQDNの最下位の名前が、5個以上連続する数字を含む ***
        fi
#
        spam_host=`echo ${from_hostname} |\
        	egrep '^([^\.]+\.)?[0-9][^\.]*\.[^\.]+\..+\.[a-z]'`
        if [ "X${spam_host}" != "X" ]
        then
            spam_exit 8 "rule 3" # *** ［ルール3］　逆引きFQDNの上位3階層を除き、最下位または下位から2番目の名前が数字で始まる ***
        fi
#
        spam_host=`echo ${from_hostname} |\
        	egrep '^[^\.]*[0-9]\.[^\.]*[0-9]-[0-9]'`
        if [ "X${spam_host}" != "X" ]
        then
            spam_exit 9 "rule 4" # *** ［ルール4］　逆引きFQDNの最下位の名前が数字で終わり、かつ下位から2番目の名前が、1個のハイフンで分断された二つ以上の数字列を含む ***
        fi
#
        spam_host=`echo ${from_hostname} |\
        	egrep '^[^\.]*[0-9]\.[^\.]*[0-9]\.[^\.]+\..+\.'`
        if [ "X${spam_host}" != "X" ]
        then
            spam_exit 10 "rule 5" # *** ［ルール5］　逆引きFQDNが5階層以上で、下位2階層の名前がともに数字で終わる ***
        fi
#
        spam_host=`echo ${from_hostname} |\
        	egrep '^(dhcp|dialup|ppp|adsl)[^\.]*[0-9]'`
        if [ "X${spam_host}" != "X" ]
        then
            spam_exit 11 "rule 6" # *** ［ルール6］　逆引きFQDNの最下位の名前が「dhcp」、「dialup」、「ppp」、または「adsl」で始まり、かつ数字を含む ***
        fi
    fi
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
			}' ${tmp}/smtp_filter.1.$$.tmp |\
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
white_ip=""
white_hostname=""
black_ip=""
black_hostname=""
#
#============================================================
#
# 直接SMTP接続分のチェック
#
# (smtp_wrapper から環境変数 SW_FROM_IP に接続元IPが渡される)
#
from_ip=${SW_FROM_IP}
#
spam_check
#============================================================
#
# メール本文を全文受信(スプール)する
#
cat >${tmp}/smtp_filter.1.$$.tmp
#============================================================
#
# 第三者中継拒否
#
from_ip=${SW_FROM_IP}
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
}' ${tmp}/smtp_filter.1.$$.tmp
#
#============================================================
#
# 後始末して終了
#
rm -f ${tmp}/smtp_filter.*.$$.tmp
exit 0
