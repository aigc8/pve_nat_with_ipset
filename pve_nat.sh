#! /bin/bash
    PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
    export PATH
    #ConfFile
    iptablesconf='/root/iptables.config.sh'
    function rootness(){
        if [[ $EUID -ne 0 ]]; then
           echo "脚本需要以ROOT权限运行!"
           exit 1
        fi
    }
    function conf_list(){
        cat $iptablesconf
    }
    function conf_add(){
        if [ ! -f $iptablesconf ];then
            echo "找不到配置文件!"
            exit 1
        fi
    echo "请选择访问控制模式:"
    echo "1) 全部开放"
    echo "2) 仅允许PVE IP白名单访问"
    read -p "请输入选项 (1 或 2): " access_mode

        echo "请输入虚拟机的内网IP"
        read -p "(Default: Exit):" confvmip
        [ -z "$confvmip" ] && exit 1
        echo
        echo "虚拟机内网IP = $confvmip"
        echo
        while true
        do
        echo "请输入虚拟机的端口:"
        read -p "(默认端口: 22):" confvmport
        [ -z "$confvmport" ] && confvmport="22"
        expr $confvmport + 0 &>/dev/null
        if [ $? -eq 0 ]; then
            if [ $confvmport -ge 1 ] && [ $confvmport -le 65535 ]; then
                echo
                echo "虚拟机端口 = $confvmport"
                echo
                break
            else
                echo "输入错误，端口范围应为1-65535!"
            fi
        else
            echo "输入错误，端口范围应为1-65535!"
        fi
        done
        echo
        while true
        do
        echo "请输入宿主机的端口"
        read -p "(默认端口: 8899):" natconfport
        [ -z "$natconfport" ] && natconfport="8899"
        expr $natconfport + 0 &>/dev/null
        if [ $? -eq 0 ]; then
            if [ $natconfport -ge 1 ] && [ $natconfport -le 65535 ]; then
                echo
                echo "宿主机端口 = $natconfport"
                echo
                break
            else
                echo "输入错误，端口范围应为1-65535!"
            fi
        else
            echo "输入错误，端口范围应为1-65535!"
        fi
        done
        echo "请输入转发协议:"
        read -p "(tcp 或者 udp ,回车默认操作: 退出):" conftype
        [ -z "$conftype" ] && exit 1
        echo
        echo "协议类型 = $conftype"
        echo
#       iptablesshell1="iptables -t nat -A PREROUTING -i eno2np1 -p $conftype --dport $natconfport -j DNAT --to-destination $confvmip:$confvmport"
#       iptablesshell2="iptables -t nat -A POSTROUTING -o vmbr0 -p $conftype --dport $confvmport -d $confvmip -j SNAT --to-source 192.168.19.1"
if [ "$access_mode" = "1" ]; then
        iptablesshell1="iptables -t nat -A PREROUTING -i eno2np1 -p $conftype --dport $natconfport -j DNAT --to-destination $confvmip:$confvmport"
        iptablesshell2="iptables -t nat -A POSTROUTING -o vmbr0 -p $conftype --dport $confvmport -d $confvmip -j SNAT --to-source 192.168.19.1"
    elif [ "$access_mode" = "2" ]; then
        iptablesshell1="iptables -t nat -A PREROUTING -i eno2np1 -p $conftype --dport $natconfport -m set --match-set PVEFW-0-ipset-v4 src -j DNAT --to-destination $confvmip:$confvmport"
        iptablesshell2="iptables -t nat -A POSTROUTING -o vmbr0 -p $conftype --dport $confvmport -d $confvmip -j SNAT --to-source 192.168.19.1"
    else
        echo "无效的选项,退出"
        exit 1
    fi
        if [ `grep -c "$iptablesshell1" $iptablesconf` != '0' ] || [ `grep -c "$iptablesshell2" $iptablesconf` != '0' ]; then
            echo "配置已经存在"
            exit 1
        fi

        get_char(){
            SAVEDSTTY=`stty -g`
            stty -echo
            stty cbreak
            dd if=/dev/tty bs=1 count=1 2> /dev/null
            stty -raw
            stty echo
            stty $SAVEDSTTY
        }
        echo
        echo "回车继续，Ctrl+C退出脚本"
        char=`get_char`
  
        echo $iptablesshell1 >> $iptablesconf
        echo $iptablesshell2 >> $iptablesconf

        runreturn1=`$iptablesshell1`
        runreturn2=`$iptablesshell2`
  
        echo $runreturn1
        echo $runreturn2

        echo '配置添加成功'
    }
    function add_confs(){
        rootness
        conf_add
    }
function del_conf(){
    echo
    while true
    do
    echo "请输入宿主机的端口"
    read -p "(默认操作: 退出):" confserverport
    [ -z "$confserverport" ] && exit 1
    expr $confserverport + 0 &>/dev/null
    if [ $? -eq 0 ]; then
        if [ $confserverport -ge 1 ] && [ $confserverport -le 65535 ]; then
            echo
            echo "宿主机端口 = $confserverport"
            echo
            break
        else
            echo "输入错误，端口范围应为1-65535!"
        fi
    else
        echo "输入错误，端口范围应为1-65535!"
    fi
    done
    echo

    # 查找 PREROUTING 规则
    iptablesshelldel1=`cat $iptablesconf | grep "PREROUTING" | grep "dport $confserverport"`
    if [ ! -n "$iptablesshelldel1" ]; then
         echo "配置文件中没有该宿主机的 PREROUTING 端口"
         exit 1
    fi

    # 从 PREROUTING 规则中提取虚拟机 IP 和端口
    confvmip=$(echo $iptablesshelldel1 | grep -oP '(?<=--to-destination )\S+' | cut -d':' -f1)
    confvmport=$(echo $iptablesshelldel1 | grep -oP '(?<=--to-destination )\S+' | cut -d':' -f2)

    # 查找对应的 POSTROUTING 规则
    iptablesshelldel2=`cat $iptablesconf | grep "POSTROUTING" | grep "dport $confvmport" | grep "$confvmip"`
    if [ ! -n "$iptablesshelldel2" ]; then
         echo "配置文件中没有对应的 POSTROUTING 规则"
         exit 1
    fi

    # 生成删除命令
    iptablesshelldelshell1=`echo ${iptablesshelldel1//-A/-D}`
    iptablesshelldelshell2=`echo ${iptablesshelldel2//-A/-D}`

    # 执行删除命令
    runreturn1=`$iptablesshelldelshell1`
    runreturn2=`$iptablesshelldelshell2`

    echo $runreturn1
    echo $runreturn2

    # 从配置文件中删除这两行
    sed -i "/$iptablesshelldel1/d" $iptablesconf
    sed -i "/$iptablesshelldel2/d" $iptablesconf

    echo '配置删除成功'
}
    function del_confs(){
        printf "你确定要删除配置吗？操作是不可逆的(y/n) "
        printf "\n"
        read -p "(默认: n):" answer
        if [ -z $answer ]; then
            answer="n"
        fi
        if [ "$answer" = "y" ]; then
            rootness
            del_conf
        else
            echo "配置删除操作取消"
        fi
    }
    action=$1
    case "$action" in
    add)
        add_confs
        ;;
    list)
        conf_list
        ;;
    del)
        del_confs
        ;;
    *)
        echo "参数错误! [${action} ]"
        echo "用法: `basename $0` {add|list|del}"
        ;;
    esac
