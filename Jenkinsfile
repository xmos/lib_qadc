// This file relates to internal XMOS infrastructure and should be ignored by external users

@Library('xmos_jenkins_shared_library@v0.35.0')

def runningOn(machine) {
  println "Stage running on:"
  println machine
}


getApproval()

pipeline {
  agent none
  environment {
    REPO = 'lib_qadc'
  } // env
  parameters {
    string(
    name: 'TOOLS_VERSION',
    defaultValue: '15.3.0',
    description: 'The XTC tools version'
    )
    string(
    name: 'XMOSDOC_VERSION',
    defaultValue: 'v6.2.0',
    description: 'The xmosdoc version'
    )
    string(
    name: 'INFR_APPS_VERSION',
    defaultValue: 'v2.0.1',
    description: 'The infr_apps version'
    )
  }
  options {
    skipDefaultCheckout()
    timestamps()
    buildDiscarder(xmosDiscardBuildSettings(onlyArtifacts=false))
  } // options
  stages {
    stage("QADC pipeline") {
      agent {
        label 'x86_64 && linux'
      }

      stages {
        stage('Checkout') {
          steps {
            runningOn(env.NODE_NAME)
            dir("${REPO}") {
                checkout scm
            } // dir
          } // steps
        } // stage 'Checkout'

        stage('Install Dependencies') {
          steps {
            dir("${REPO}") {
              withTools(params.TOOLS_VERSION) {
                dir("examples"){
                  sh "cmake -G 'Unix Makefiles' -B build"
                }
                createVenv("requirements.txt")
                withVenv {
                  sh "pip install -r requirements.txt"
                 }
              }
            }
          }
        }
        stage('Lib and code checks') {
          steps {
            dir("${REPO}") {
              withVenv {
                warnError("Lib checks") {
                  runLibraryChecks("${WORKSPACE}/${REPO}", "${params.INFR_APPS_VERSION}")
                }
              }
            }
          }
        }
        stage('Docs') {
          steps {
            dir("${REPO}") {
              withVenv {
                warnError("Docs") {
                  buildDocs()
                }
              }
            }
          }
        } // stage: Docs
        stage('Build Examples') {
          steps {
            dir("${REPO}/examples") {
              withTools(params.TOOLS_VERSION) {
                sh "cmake -G 'Unix Makefiles' -B build"
                sh "xmake -C build -j 8"
              } // withTools
            } // dir
          } // steps
        } // stage 'Build'
        stage('Tests') {
          steps { 
            dir("${REPO}/tests") {
              withVenv {
                withTools(params.TOOLS_VERSION) {
                  sh "cmake -G 'Unix Makefiles' -B build"
                  sh "xmake -C build -j 8"
                  runPytest("-vv")
                } // withTools
              } // withVenv
            } // dir
          } // steps
        } // Tests
      } // stages
      post {
        always {
          archiveArtifacts artifacts: "**/tests/*.png", fingerprint: true, allowEmptyArchive: true
        }
        cleanup {
          xcoreCleanSandbox()
        }
      }
    } // stage: xcore.ai
  } // stages
} // pipeline
