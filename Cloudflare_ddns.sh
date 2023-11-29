#!/bin/bash

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
Normal='\033[0m'
cyan='\033[0;36m'

config_file="config.txt"

# 检查配置文件是否存在
if [ -f "$config_file" ]; then
    # 如果存在，读取配置信息
    source "$config_file"
    echo -e "${GREEN}已检测到配置文件，将使用保存的配置信息。${NC}"
else
    echo -e "${RED}未检测到配置文件，请手动更新配置信息。${NC}"

    # 创建配置文件
    touch "$config_file" || { echo "无法创建配置文件 $config_file"; exit 1; }
fi

# 函数：手动更新配置信息
update_config() {
    read -p "请输入你的Cloudflare注册账户邮箱(auth_email): " auth_email
    read -p "请输入你的Cloudflare账户Globel ID(auth_key): " auth_key
    read -p "请输入你的主域名(zone_name): " zone_name
    read -p "请输入你需要更新的完整的DDNS解析域名(record_name): " record_name
    read -p "请输入DNS记录类型(A或AAAA): " record_type
    read -p "请输入IP获取方式(internet或local): " ip_index

    # 保存配置信息到文件
    echo "auth_email=\"$auth_email\"" > "$config_file"
    echo "auth_key=\"$auth_key\"" >> "$config_file"
    echo "zone_name=\"$zone_name\"" >> "$config_file"
    echo "record_name=\"$record_name\"" >> "$config_file"
    echo "record_type=\"$record_type\"" >> "$config_file"
    echo "ip_index=\"$ip_index\"" >> "$config_file"

    echo -e "${GREEN}配置信息已更新。${NC}"
}

# 如果存在配置文件，则提示用户是否手动更新配置
if [ -f "$config_file" ]; then
    read -p "是否手动更新配置信息？ (y/n): " update_config_prompt

    if [ "$update_config_prompt" == "y" ]; then
        # 调用手动更新配置信息的函数
        update_config
    else
        echo -e "${RED}更新已取消。${NC}"
    fi
fi
# 检查是否已存在定时任务
if ! crontab -l | grep -q "*/5 * * * *  bash /root/Cloudflare_ddns.sh"; then
    # 添加定时任务
    (crontab -l ; echo "*/5 * * * *  bash /root/Cloudflare_ddns.sh") | crontab -
fi

# 检查是否已存在日志清空任务
if ! crontab -l | grep -q "> /root/cloudflare_ddns.log"; then
    # 添加日志清空任务
    (crontab -l ; echo "0 * * * * > /root/cloudflare_ddns.log") | crontab -
fi

# 其他配置信息
ipv4_api="ipv4.icanhazip.com"
ipv6_api="api6.ipify.org"
ip_file="ip.txt"
id_file="cloudflare_ddns.ids"
log_file="cloudflare_ddns.log"

# 日志
log() {
    if [ "$1" ]; then
        echo -e "[$(date '+%Y年%m月%d日 %H:%M:%S')] - $1" >> "$log_file"
    fi
}
#获取域名和授权
if [ -f $id_file ] && [ $(wc -l $id_file | cut -d " " -f 1) == 2 ]; then
    zone_identifier=$(head -1 $id_file)
    record_identifier=$(tail -1 $id_file)
else
    zone_identifier=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone_name" -H "X-Auth-Email: $auth_email" -H "X-Auth-Key: $auth_key" -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1 )
    record_identifier=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?name=$record_name" -H "X-Auth-Email: $auth_email" -H "X-Auth-Key: $auth_key" -H "Content-Type: application/json"  | grep -Po '(?<="id":")[^"]*' | head -1 )
    echo "$zone_identifier" > $id_file
    if [ $zone_identifier == $(head -1 $id_file) ] && [ -n "$zone_identifier" ]; then
        echo -e "${GREEN}获取zone_id成功!${NC}"
        log "获取zone_id成功!"
    else 
        echo -e "${RED}获取zone_id失败!请检查网络和Globel ID是否正确并删除cloudflare_ddns.ids文件后从新运行!${NC}"
        log "获取zone_id失败!请检查网络和Globel ID是否正确并删除cloudflare_ddns.ids文件后从新运行."
        exit
    fi
    echo "$record_identifier" >> $id_file
    if [ $record_identifier == $(tail -1 $id_file) ] && [ -n "$record_identifier" ]; then
        echo -e "${GREEN}获取record_id成功!${NC}"
        log "获取record_id成功!"
        echo -e "${GREEN}第一次运行,无上次IP!${NC}" > $ip_file
        echo -e "${GREEN}创建ip.txt文件成功!${NC}"
    else 
        echo -e "${RED}获取record_id失败!请检查网络和Globel ID是否正确并删除cloudflare_ddns.ids文件后从新运行!${NC}"
        log "获取record_id失败!请检查网络和Globel ID是否正确并删除cloudflare_ddns.ids文件后从新运行."
        exit
    fi
fi
# 判断是A记录还是AAAA记录
if [ $record_type = "A" ];then
    if [ $ip_index = "internet" ];then
        ip=$(curl -s $ipv4_api)
        echo -e "${GREEN}网络获取IPV4成功!IP:$ip${NC}"
        log "网络获取IPV4成功!IP:$ip"
    elif [ $ip_index = "local" ];then
        ip=$(/sbin/ifconfig $eth_card | grep 'inet'| grep -v '127.0.0.1' | grep -v 'inet6'|cut -f2 | awk '{ print $2}' | head -1)
        if [ -n "$ip" ];then
            echo -e "${GREEN}本地获取IPV4成功!IP:$ip${NC}"
            log "本地获取IPV4成功!IP:$ip"
        else 
            echo -e "${RED}IP获取错误,请输入正确的获取方式!${NC}"
            log "IP获取错误,请输入正确的获取方式!"
            exit
        fi
    fi
elif [ $record_type = "AAAA" ];then
    if [ $ip_index = "internet" ];then
        ip=$(curl -s $ipv6_api)
        echo -e "${GREEN}网络获取IPV6成功!IP:$ip${NC}"
        log "网络获取IPV6成功!IP:$ip"
    elif [ $ip_index = "local" ];then
        ip=$(/sbin/ifconfig $eth_card | grep 'inet6'| grep -v '::1'|grep -v 'fe80' | cut -f2 | awk '{ print $2}' | tail -1)
        if [ -n "$ip" ];then
            echo -e "${GREEN}本地获取IPV6成功!IP:$ip${NC}"
            log "本地获取IPV6成功!IP:$ip"
        else 
            echo -e "${RED}IP获取错误,请输入正确的获取方式!${NC}"
            log "IP获取错误,请输入正确的获取方式!"
            exit
        fi
    fi
else
    echo -e "${RED}DNS类型错误!${NC}"
    log "DNS类型错误!"
    exit
fi
# 检查开始
log "检查中!"
#判断ip是否发生变化
if [ -f $ip_file ]; then
    old_ip=$(cat $ip_file)
    if [ $ip == $old_ip ]; then
        echo -e "${YELLOW}IP没有更改!${NC}"
        log "IP没有更改!"
        log "----------------------------------------------------------------------"
        exit
    fi
fi
#更新DNS记录
update=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" -H "X-Auth-Email: $auth_email" -H "X-Auth-Key: $auth_key" -H "Content-Type: application/json" --data "{\"type\":\"$record_type\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":600,\"proxied\":false}")
#反馈更新情况
if [ "$update" != "${update%success*}" ] && [ "$(echo $update | grep "\"success\":true")" != "" ]; then
    echo -e "${GREEN}更新成功啦!${NC}"
    echo -e "${GREEN}上次IP:$(cat $ip_file)${NC}"
    echo -e "${GREEN}本次IP:$ip${NC}"
    log "更新成功啦!"
    log "上次IP:$(cat $ip_file)"
    log "本次IP:$ip"
    log "----------------------------------------------------------------------"
    echo $ip > $ip_file
    exit
else
    echo -e "${RED}更新失败啦!回复为空请检查网络,回复为1001获取record_id失败,回复7000获取zone_id失败!${NC}"
    echo -e "${RED}回复: $update${NC}"
    log "更新失败啦!"
    log "回复: $update"
    log "----------------------------------------------------------------------"
    exit
fi
