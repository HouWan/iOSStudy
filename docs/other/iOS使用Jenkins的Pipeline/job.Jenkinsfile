// =========================================================================================

// APP项目的Target数据
def k_app_targets = ['MYApp_Test', 'MYApp_Door', 'MYApp_AppStore', 'MYApp_AppStore', 'MYApp_enterprise']
// APP项目的Target数据描述
def k_app_targets_info = '''👆🏻对各个分支的说明：（注意<线上包>不允许使用此Job处理）
😋 MYApp_Test 测试包，常用
😭 MYApp_Door 线上-后门包，常用
😍 MYApp_AppStore 线上包
😌 MYApp_enterprise 企业包
'''

// =========================================================================================

pipeline {
    agent any

    // 定义全局变量
    environment {
        // Git提交信息
        GIT_COMMIT = ""
        // 飞书机器人web hook
        FEISHU_HOOK = "https://oapi.dingtalk.com/robot/send?access_token=a7d17edd352"
    }

    // 定义流水线运行时的配置选项，流水线提供了许多选项
    options {
        timestamps()  // 日志会有时间
        timeout(time: 1, unit: 'HOURS')  // 流水线超时时间
        disableConcurrentBuilds()  // 禁止并行
    }

    // 为流水线运行时设置项目相关的参数，就不用在UI界面上定义了，比较方便。
    parameters {
        choice(name: 'TARGET_NAME', choices: k_app_targets, description: k_app_targets_info)

        // 注意，此参数需要依赖`Git Parameter`插件，注意查看是否已安装此插件
        // https://plugins.jenkins.io/git-parameter/
        gitParameter(branch: '',
                     branchFilter: 'origin/(.*)',
                     defaultValue: 'preRelease',
                     description: '👆🏻请输入需要编译的分支名称',
                     sortMode: 'DESCENDING_SMART',
                     name: 'GIT_BRANCH',
                     type: 'PT_BRANCH')

        text(name: 'MSG_REMARK', defaultValue: '无', description: '👆🏻请输入备注信息，会跟随飞书通知一起发送')
    }

    stages {
        stage('拉取代码') {
            steps {
                // 😭注意，credentialsId和url的正确配置。
                git branch: "${params.GIT_BRANCH}", credentialsId: '3b37fb3e-0d77-4fa5-be9c-31d1b4e52450', url: 'git@gitlab.yc345.tv:ios/apps/YCMath-iOS.git'
                println("Git拉取代码")
            }
        }

        stage('Pod脚本') {
            steps {
                println("Pod脚本")
            }
        }

        stage('Archive归档') {
            steps {
                println("编译")
            }
        }

        stage('Export导出') {
            steps {
                println("编译")
            }
        }

        stage('上传蒲公英') {
            steps {
                println("上传蒲公英")
            }
        }

        stage('通知飞书') {
            steps {
                println("通知飞书")
            }
        }
    }
}