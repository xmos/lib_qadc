@Library('xmos_jenkins_shared_library@v0.34.0')

def runningOn(machine) {
  println "Stage running on:"
  println machine
}

def buildApps(appList) {
  appList.each { app ->
    sh "cmake -G 'Unix Makefiles' -B build"
    sh "xmake -C build -j\$(nproc)"
  }
}


getApproval()

pipeline {
  agent none
  parameters {
    string(
      name: 'TOOLS_VERSION',
      defaultValue: '15.3.0',
      description: 'The tools version to build with (check /projects/tools/ReleasesTools/)'
    )
  } // parameters
  environment {
    REPO = 'lib_qadc'
    PIP_VERSION = "24.0"
    PYTHON_VERSION = "3.11"
    XMOSDOC_VERSION = "v6.1.2"          
  } // env
  options {
    skipDefaultCheckout()
    timestamps()
    buildDiscarder(xmosDiscardBuildSettings(onlyArtifacts=false))
  } // options
  stages {
    stage('xcore.ai') {
      agent {
        label 'xcore.ai' // xcore.ai nodes have 2 devices atatched, allowing parallel HW test
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
                createVenv("requirements.txt")
                withVenv {
                  sh "pip install -r requirements.txt"
                 }
              }
            }
          }
        }
        stage('Static analysis') {
          steps {
            dir("${REPO}") {
              withVenv {
                warnError("Flake") {
                  sh "flake8 --exit-zero --output-file=flake8.xml lib_qadc"
                  recordIssues enabledForFailure: true, tool: flake8(pattern: 'flake8.xml')
                }
                warnError("Lib checks") {
                  runLibraryChecks("${WORKSPACE}/${REPO}", "v2.0.1")
                }
              }
            }
          }
        }
        stage('Build') {
          steps {
            sh "git clone -b develop git@github.com:xmos/xcommon_cmake ${WORKSPACE}/xcommon_cmake"
            dir("${REPO}/example") {
              withTools(params.TOOLS_VERSION) {
                withEnv(["XMOS_CMAKE_PATH=${WORKSPACE}/xcommon_cmake"]) {
                  dir("pot_reader"){
                    buildApps([
                      "qadc_pot_example"
                    ]) // buildApps
                  } // dir
                  dir("rheo_reader"){
                    buildApps([
                      "qadc_rheo_example"
                    ]) // buildApps
                  } // dir
                } // withEnv
              } // withTools
            } // dir
          } // steps
        } // stage 'Build'
        stage('Tests') {
          steps { 
            dir("${REPO}/tests") {
              withEnv(["XMOS_CMAKE_PATH=${WORKSPACE}/xcommon_cmake"]) {
                withVenv {
                  withTools(params.TOOLS_VERSION) {
                    // sh 'python -m pytest --junitxml=pytest_result.xml'
                    // Find out why pytest fails..
                    sh 'python test_qadc_model_tolerance.py'
                    sh 'python test_qadc_pot_lut.py'
                  } // withTools
                } // withVenv
              } // withEnv
            } // dir
          } // steps
        } // Tests
      } // stages
      post {
        always {
          archiveArtifacts artifacts: "**/tests/*.png", fingerprint: true, allowEmptyArchive: true
          // junit '**/reports/*.xml'
          // TODO re-enable when using Pytest
        }
        cleanup {
          xcoreCleanSandbox()
        }
      }
    } // stage: xcore.ai
    stage('Docs') {
      agent {
        label 'documentation'
      }
      steps {
        runningOn(env.NODE_NAME)
        dir("${REPO}") {
          checkout scm
          createVenv("requirements.txt")
          withTools(params.TOOLS_VERSION) {
            buildDocs("lib_qadc.zip")
          }
        }
      }
      post {
        cleanup {
          cleanWs()
        }
      }
    } // stage: Docs

  } // stages
} // pipeline
