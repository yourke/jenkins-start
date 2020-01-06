#! /bin/sh
# set -e的作用是遇到错误则停止执行脚本
set -e
# 保证环境变量能生效？不加执行java命令时可能报错
source /etc/profile

# 此脚本主要功能：
# 1.动态获取当前模块名（通过解析传递过来的pom.xml获得）
# 2.杀死与当前模块相关所有进程
# 3.备份当前目录下所有已存在的war包
# 4.启动当前模块
# 5.打印数秒启动日志

# 默认当前脚本在指定模块的部署根路径，同时存在最新以temp后缀的最新war包
echo "---------------------------------------执行start.sh开始---------------------------------------"
# 指定临时包文件后缀名
postfix="temp"
# 指定日志打印时间(s)
show_time=60

# 0.预处理，判断部署所需文件是否存在
echo "脚本环境信息"
# 当前脚本所处路径
base_project_path=$(cd `dirname $0`;pwd)
echo " > 当前start.sh脚本所处路径: ${base_project_path}"
# 进入该路径，将当前工作目录转到该路径中，后面路径都是相对当前路径，直接cd似乎没用？
#cd `${base_project_path}`
echo " > 当前工作目录: $(pwd)"
# 判断是否存在pom.xml，不存在则不执行
if [ ! -f "${base_project_path}/pom.xml" ]
then
    echo "临时pom.xml文件不存在，中止运行！";
    exit 1;
fi

# 脚本参数信息
echo "脚本参数信息"
# 启动参数
params=$*
if [ "${params}" = "" ]; then
    echo " > 启动参数为空，使用默认值"
else
    echo " > 启动参数: ${params}"
    # 参数校验，springboot参数需以"--"开头
    for param in "$@"
    do
        if !([[ ${param} == --* ]]); then
            echo " > 参数\"${param}\"无效，需以\"--\"开头。中止运行！"
            exit 1;
        fi
    done
fi


# 1.动态获取当前模块名（根据传递过来的pom.xml查找，根据war名称来也可以，不过不一定准确）
echo "当前模块信息"
# 清除pom文件中可能存在的windows换行符"^M"，避免获取的变量值异常
sed -i 's/\r//g' ${base_project_path}/pom.xml
# jenkins中指定的war信息，直接去找pom文件找
project_name=`awk '/<artifactId>[^<]+<\/artifactId>/{gsub(/<artifactId>|<\/artifactId>/,"",$1);print $1;exit;}' ${base_project_path}/pom.xml`
project_version=`awk '/<version>[^<]+<\/version>/{gsub(/<version>|<\/version>/,"",$1);print $1;exit;}' ${base_project_path}/pom.xml`
project_packaging=`awk '/<packaging>[^<]+<\/packaging>/{gsub(/<packaging>|<\/packaging>/,"",$1);print $1;exit;}' ${base_project_path}/pom.xml`
if [ "${project_packaging}" = "" ]; then
    # pom中packaging为空，默认为jar包
    project_packaging="jar"
fi
echo " > 模块名称: ${project_name}"
echo " > 模块版本: ${project_version}"
echo " > 模块类别: ${project_packaging}"
# 指定版本完整包名
package_name="${project_name}-${project_version}.${project_packaging}"
echo " > 模块包名: ${package_name}"
# 指定版本完整临时包名
temp_package_name="${project_name}-${project_version}.${postfix}"
echo " > 模块临时包名: ${temp_package_name}"

# 检查获取到的字符串的格式，直接输出到文件后查看是否包含特殊字符
# echo  "A"${package_name}"Z" >> temp.txt

# 判断是否存在指定war包，不存在则不执行
if [ ! -f "${base_project_path}/${temp_package_name}" ]
then
    echo "pom.xml对应版本的${postfix}后缀文件不存在，中止运行！";
    exit 1;
fi


# 2.杀死与当前模块相关所有进程
# 找到上次启动的包进程，kill掉（注意这里查询相关进程时，别把当前脚本进程杀掉了！！！）
echo "开始Kill旧进程"
pids=$(ps -ef | grep ${project_name} | grep jar| grep -v grep | awk '{print $2}')
if [ -n "${pids}" ]
then
    for pid in ${pids}
    do
        kill -9 ${pid}
        echo " > 旧进程: ${pid} kill完成！"
    done
else
    echo " > 无相关旧进程，跳过！"
fi


# 3.备份当前目录下所有已有war包
echo "开始备份旧包"
files=$(ls ${base_project_path}/*.${project_packaging} 2> /dev/null | wc -l)
if [ "${files}" != "0" ]
then
    #判断备份路径是否存在
    backdir="${base_project_path}/backup"
    if [ ! -d ${backdir} ]
    then
        mkdir ${backdir}
        echo " > 备份路径: ${backdir} 不存在，已默认创建"
    fi
    #移动且重命名所有已存在的war包
    for file in $(ls ${base_project_path}/. | grep .${project_packaging})
    do
        mv ${base_project_path}/${file} ${backdir}/${file}.bak_$(date "+%Y%m%d-%H%M%S")
        echo " > 旧包: ${file} 备份完成！"
    done
else
    echo " > 无相关旧包，跳过！"
fi


# 4.启动当前模块
echo "开始启动新包"
package_path=${base_project_path}/${package_name}
# 还原当前war包名
mv ${base_project_path}/${temp_package_name} ${package_path}
# 启动新包
echo " > 修改新包权限"
chmod 0755 ${package_path}
echo " > 执行启动命令：nohup java -jar -Xmx1g -Xms1g ${package_path} ${params} >/dev/null 2>&1 &"
nohup java -jar -Xmx1g -Xms1g ${package_path} ${params} >/dev/null 2>&1 &
echo " > 启动命令执行完成！"

# 删除临时文件
echo "开始删除部署产生的临时文件"
rm -f ${base_project_path}/pom.xml
# 可能存在其他版本war包临时文件存在，也进行删除
rm -f ${base_project_path}/*.${postfix}
echo " > 临时文件删除完成！"


# 5.并打印数秒启动日志
echo "--------------打印${show_time}秒当前war包的启动日志--------------"
# 等待，避免日志文件还未生成的情况
if [ ! -f "${base_project_path}/${project_name}.log" ]
then
    sleep 10
fi
# 查看日志
tail -f ${base_project_path}/${project_name}.log &
# 睡眠指定时间后kill掉打印的子进程
childPId=$!
sleep ${show_time}
kill -9 ${childPId}
echo "--------------启动日志打印完成--------------"

echo "---------------------------------------执行start.sh结束---------------------------------------"