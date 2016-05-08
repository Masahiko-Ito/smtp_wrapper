#! /bin/ash
#
# This part of smtp_wrapper-0.2 is distributed under GNU General Public License.
#
# Sample null filter script
#   by "Masahiko Ito" <m-ito@mbox.kyoto-inet.or.jp>
#
# smtp_wrapperデバッグ用
# 第三者中継チェックすらしてないので注意
#
#------------------------------------------------------------
PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
export PATH
#------------------------------------------------------------
tmp="/var/tmp"
#------------------------------------------------------------
cat >${tmp}/smtp_filter.1.$$.tmp
#
cat ${tmp}/smtp_filter.*.$$.tmp |\
awk 'BEGIN{
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
}'
#
rm -f ${tmp}/smtp_filter.*.$$.tmp
exit 0
