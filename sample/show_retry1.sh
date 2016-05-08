#! /bin/sh
#
# This part of smtp_wrapper is distributed under GNU General Public License.
#
# show today's retry mail
#
# ex. cat /var/log/maillog | show_retry1.sh
#
PATH="/usr/local/smtp_wrapper:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"; export PATH
tmp="/tmp"
#----------------------------------------------------------------- 
#
# 当日中の、完全に全てのアクセスを拒否されているIPの内、
# INTERVALに設定した秒数以上間隔を空けてアクセスしてい
# る物を表示する。
#
# RFC2821(Simple Mail Transfer Protocol)
#
# 4.5.4.1 送信戦略 
#
# ある特定の宛先への送信が失敗した後、クライアントは再送を遅延させ
# なければならない(MUST)。一般にこの再送の間隔は少なくとも 30 分で
# あるべき(SHOULD)だが、配送不能の原因を SMTP クライアントが特定で
# きる場合には、より繊細で柔軟な戦略が有益だろう。 
#
INTERVAL=`expr 30 \* 60`; export INTERVAL
#
date=`date +'%b %d' | sed -e 's/  *0/ /'`
#
# In : May 23 10:59:35 lib100 smtp_wrapper: [25403] 450 This message was rejected according to site policy(rejected by ip_filter. IP=60.236.0.5)(SL18)
#
# 当日中の、IPを含んだ(拒否|受付)メッセージを抽出[1]
cat $* |\
sed -e 's/  */ /g' |\
egrep -i "^${date} .*smtp_wrapper.*rejected by|^${date} .*smtp_wrapper.*child start" >${tmp}/show_retry1.1.$$.tmp
#
# 受付メッセージから出現回数、IPを抽出＆編集[2]
cat ${tmp}/show_retry1.1.$$.tmp |\
grep -i 'child start' |\
sed -e 's/^.*IP=//;s/(.*$//' |\
sort |\
uniq -c |\
grep -v  '^ *1 ' |\
sort >${tmp}/show_retry1.2.$$.tmp
#
# 拒否メッセージから出現回数、IPを抽出＆編集[3]
cat ${tmp}/show_retry1.1.$$.tmp |\
grep -i 'rejected by' |\
sed -e 's/^.*IP=//;s/).*$//' |\
sort |\
uniq -c |\
sort >${tmp}/show_retry1.3.$$.tmp
#
# 受付回数と拒否回数の等しい(つまり完全に拒否されている)IPを抽出[4]
join -t "," ${tmp}/show_retry1.2.$$.tmp ${tmp}/show_retry1.3.$$.tmp |\
sed -e 's/^ *//' |\
cut -d ' ' -f 2 |\
sort >${tmp}/show_retry1.4.$$.tmp
#
# 拒否メッセージの間隔がINTERVAL秒以上のIP抽出＆編集[5]
cat ${tmp}/show_retry1.1.$$.tmp |\
grep -i "smtp_wrapper.*rejected by" |\
sed -e 's/smtp_wrapper:.*IP=//;s/).*$//;s/:/ /g' |\
sort -t ' ' +6 -7 +2 -5 |\
#
# In : May 23 11 10 04 lib100 61.211.239.162
#
awk 'BEGIN{
	FS = " ";
	ip = "";
	rapid = "";
	interval = ENVIRON["INTERVAL"]
}
{
	if (ip == ""){
		time = ($3 * 3600) + ($4 * 60) + $5
		ip = $7;
		rapid = "";
	}else{
		if (ip == $7){
			time_next = ($3 * 3600) + ($4 * 60) + $5
			if (rapid == "YES"){
				/* do nothing */;
			}else{
				if ((time_next - time) < interval){
					rapid = "YES";
				}else{
					rapid = "NO";
				}
			}
			time = time_next;
		}else{
			if (rapid == "NO"){
				print ip;
			}
			time = ($3 * 3600) + ($4 * 60) + $5
			ip = $7;
			rapid = "";
		}
	}
}
END{
	if (rapid == "NO"){
		print ip;
	}
}' >${tmp}/show_retry1.5.$$.tmp
#
# [4][5]マッチングして、全ての受付がINTERVAL秒以上の間隔で拒否されているIPを抽出[6]
join ${tmp}/show_retry1.4.$$.tmp ${tmp}/show_retry1.5.$$.tmp >${tmp}/show_retry1.6.$$.tmp
#
# [6]にDNS逆引結果を付加して表示
for i in `cat ${tmp}/show_retry1.6.$$.tmp`
do
	echo -n $i " : "
	host $i
done
#
rm -f ${tmp}/show_retry1.*.$$.tmp
