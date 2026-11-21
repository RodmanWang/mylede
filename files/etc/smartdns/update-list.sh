#!/bin/sh
#
# SmartDNS 规则自动更新脚本
#

TMP="/tmp/smartdns"
URL="https://gitea.goota.top/RodmanWang/ChinaIP-and-GFW/raw/branch/release"

mkdir -p "$TMP" || exit 1

# 下载函数：失败重试3次，下载完成检查文件大小
download() {
    url="$1"
    file="$2"

    rm -f "$file"

    i=1
    while [ "$i" -le 3 ]; do
        echo "正在下载：$url"

        if wget -q -T 30 -t 1 -O "$file" "$url" &&
           [ -s "$file" ]; then
            echo "下载成功：$file"
            return 0
        fi

        echo "下载失败，5秒后重试（$i/3）"
        rm -f "$file"
        sleep 5
        i=$((i + 1))
    done

    echo "错误：下载失败 $url"
    return 1
}

# 下载规则
download "$URL/GFW.txt" "$TMP/GFW.conf" || exit 1
download "$URL/ChinaDomain3.conf" "$TMP/ChinaDomain.conf" || exit 1
download "$URL/ChinaIP.txt" "$TMP/BlacklistIP.conf" || exit 1
download "$URL/ChinaIP.txt" "$TMP/WhitelistIP.conf" || exit 1

#download "$URL/BogusNxdomain.conf" "$TMP/BogusNxdomain.conf" || exit 1
#download "https://gitea.goota.top/RodmanWang/ad/raw/branch/ad/ad-smartdns.conf" "$TMP/AD.conf" || exit 1

# 所有启用的下载完成后才开始更新
echo "所有规则下载成功，开始更新配置"

#mv -f "$TMP/GFW.conf" /etc/smartdns/domain-set/GFW.conf
mv -f "$TMP/BlacklistIP.conf" /etc/smartdns/ip-set/BlacklistIP.conf || exit 1
mv -f "$TMP/WhitelistIP.conf" /etc/smartdns/ip-set/WhitelistIP.conf || exit 1
mv -f "$TMP/ChinaDomain.conf" /etc/smartdns/domain-set/ChinaDomain.conf || exit 1
#mv -f "$TMP/BogusNxdomain.conf" /etc/smartdns/conf.d/BogusNxdomain.conf
#mv -f "$TMP/AD.conf" /etc/smartdns/conf.d/AD.conf

# 清理临时文件
rm -rf "$TMP"

# 重启 SmartDNS
/etc/init.d/smartdns restart

echo "SmartDNS 规则更新完成：$(date)"
#