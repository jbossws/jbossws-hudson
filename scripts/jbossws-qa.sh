#!/bin/sh

ensureJavaExists() {
  if [ ! -d $JAVA_HOME ]; then
    echo "Please point java.home specified in ant.properties to correct JDK installations"
    exit 1
  fi
}

setupJBossHome() {
  rm -rf $WORKSPACE/jboss-as
  cp -r $JBOSS_INSTANCE $WORKSPACE/jboss-as
  export JBOSS_HOME=$WORKSPACE/jboss-as
  echo "Overwriting default application-users.properties / application-roles.properties on AS..."
  cp $STACK_DIR/etc/application-*.properties $JBOSS_HOME/standalone/configuration
}

setupEnv() {
  TMP_DIR_PROPERTY=
  if [ -d /data/tmp ]; then
    TMP_DIR_PROPERTY=-Djava.io.tmpdir=/data/tmp
  elif [ -d /tmp ]; then
    TMP_DIR_PROPERTY=-Djava.io.tmpdir=/tmp
  else
    echo "Cannot detect temporary directory";
    exit -1;
  fi

  ENVIRONMENT="$TMP_DIR_PROPERTY -Dmaven.opts=-U -Djboss.bind.address=$JBOSS_BIND_ADDRESS -Djbossws.integration.target=$JBOSS_TARGET -D$JBOSS_TARGET.home=$JBOSS_HOME"
}

stopJBoss() {
  $SCRIPTS_DIR/jboss.sh $JBOSS_HOME stop $JBOSS_BIND_ADDRESS
}

startJBoss() {
  #Debug use: remove this later
  if [ -e cxf-api-2.7.10.jar ]; then
    rm  cxf-api-2.7.10.jar
  fi
  wget http://people.apache.org/~ema/cxf-api-2.7.10.jar
  ls -all cxf-api-2.7.10.jar
  ls -all $JBOSS_HOME/modules/system/layers/base/org/apache/cxf/main/
  cp cxf-api-2.7.10.jar $JBOSS_HOME/modules/system/layers/base/org/apache/cxf/main/cxf-api.jar
  ls -all $JBOSS_HOME/modules/system/layers/base/org/apache/cxf/main

  if [ -e cxf-rt-ws-security-2.7.10.jar ]; then
    rm  cxf-rt-ws-security-2.7.10.jar
  fi
  wget http://people.apache.org/~ema/cxf-rt-ws-security-2.7.10.jar
  ls -all cxf-rt-ws-security-2.7.10.jar
  ls -all $JBOSS_HOME/modules/system/layers/base/org/apache/cxf/impl/main/cxf-rt-ws-security.jar
  cp cxf-rt-ws-security-2.7.10.jar $JBOSS_HOME/modules/system/layers/base/org/apache/cxf/impl/main/cxf-rt-ws-security.jar
  ls -all $JBOSS_HOME/modules/system/layers/base/org/apache/cxf/impl/main/cxf-rt-ws-security.jar  
  #Debug use END

  $SCRIPTS_DIR/jboss.sh $JBOSS_HOME start $JBOSS_BIND_ADDRESS
}

copyJBossLogs() {
  if [ -e $JBOSS_HOME/standalone/log/boot.log ]; then
    cp $JBOSS_HOME/standalone/log/boot.log $WORKSPACE/jboss-boot.log
  fi
  cp $JBOSS_HOME/standalone/log/server.log $WORKSPACE/jboss-server.log
}

copyTestLogs() {
  cat $WORKSPACE/tests.log | egrep FIXME\|FAILED | sort -u | tee $WORKSPACE/fixme.txt
  cat $STACK_DIR/modules/dist/target/exclude-file/test-excludes-$JBOSS_TARGET.txt $WORKSPACE/fixme.txt | egrep "\[\S*]" > $WORKSPACE/errata-$JBOSS_TARGET.txt
}

removeJBossLogs() {
  rm -f $JBOSS_HOME/standalone/log/boot.log
  rm -f $JBOSS_HOME/standalone/log/server.log
}

ensureRunningJBoss() {
    $SCRIPTS_DIR/http-spider.sh $JBOSS_BIND_ADDRESS:8080 $WORKSPACE
    if [ -e $WORKSPACE/spider.failed ]; then
      tail -n 100 $JBOSS_HOME/standalone/log/server.log
      stopJBoss
      copyJBossLogs
      exit 1
    fi
#    sleep 5 
}

logMavenDependencies() {
  mvn -Ptestsuite,$JBOSS_TARGET dependency:tree | tee $WORKSPACE/dependency-tree.txt
}

deployCoreDistributionWithSpring() {
  cd $STACK_DIR
  mvn -Ptestsuite,dist,spring clean
  ant $ENVIRONMENT -Dspring=true deploy-$JBOSS_TARGET
}

deployCoreDistribution() {
  cd $STACK_DIR
  mvn -Ptestsuite,dist clean
  ant $ENVIRONMENT deploy-$JBOSS_TARGET
}

deployBinaryDistributionWithSpring() {
  cd $STACK_DIR
  mvn -Ptestsuite,dist clean
  ant $ENVIRONMENT build-bin-dist
  cd target
  rm -rf jbossws-$STACK_ID-bin-dist
  unzip jbossws-$STACK_ID-bin-dist.zip
  cd jbossws-$STACK_ID-bin-dist
  cp ant.properties.example ant.properties
  ant $ENVIRONMENT -Dspring=true deploy-$JBOSS_TARGET
}

deployBinaryDistribution() {
  cd $STACK_DIR
  mvn -Ptestsuite,dist clean
  ant $ENVIRONMENT build-bin-dist
  cd target
  rm -rf jbossws-$STACK_ID-bin-dist
  unzip jbossws-$STACK_ID-bin-dist.zip
  cd jbossws-$STACK_ID-bin-dist
  cp ant.properties.example ant.properties
  ant $ENVIRONMENT deploy-$JBOSS_TARGET
}

redeployBinaryDistribution() {
  cd $STACK_DIR/target/jbossws-$STACK_ID-bin-dist
  ant clean
  ant $ENVIRONMENT deploy-$JBOSS_TARGET
}

deploySourceDistributionWithSpring() {
  cd $STACK_DIR
  mvn -Ptestsuite,dist,spring clean
  ant $ENVIRONMENT build-src-dist
  cd target
  rm -rf jbossws-$STACK_ID-src-dist
  unzip jbossws-$STACK_ID-src-dist.zip
  cd jbossws-$STACK_ID-src-dist
  ant $ENVIRONMENT -Dspring=true deploy-$JBOSS_TARGET
}

deploySourceDistribution() {
  cd $STACK_DIR
  mvn -Ptestsuite,dist clean
  ant $ENVIRONMENT build-src-dist
  cd target
  rm -rf jbossws-$STACK_ID-src-dist
  unzip jbossws-$STACK_ID-src-dist.zip
  cd jbossws-$STACK_ID-src-dist
  ant $ENVIRONMENT deploy-$JBOSS_TARGET
}

detectFailures() {
  #rm -rf $WORKSPACE/jboss-as
  cat $WORKSPACE/tests.log | egrep "BUILD FAILURE|BUILD ERROR|java.lang.OutOfMemoryError" | tee $WORKSPACE/failure.log
  if [ -s $WORKSPACE/failure.log ]; then
    echo "Failure detected"
    exit 1
  fi
}

runTestsViaMavenWithSpring() {
  mvn $ENVIRONMENT -Ptestsuite,hudson,spring,$JBOSS_TARGET $TEST_OPTS integration-test 2>&1 | tee $WORKSPACE/tests.log
}

runTestsViaMaven() {
  mvn $ENVIRONMENT -Ptestsuite,hudson,$JBOSS_TARGET $TEST_OPTS integration-test 2>&1 | tee $WORKSPACE/tests.log
}

runTestsViaAnt() {
  ant $ENVIRONMENT tests-clean tests $TEST_OPTS 2>&1 | tee $WORKSPACE/tests.log
}

addTestQueue() {
  if [ "$JBOSS_TARGET" != "jboss710" ] && [ "$JBOSS_TARGET" != "jboss711" ]; then
    sleep 10
    $JBOSS_HOME/bin/jboss-cli.sh -c command="/subsystem=messaging/hornetq-server=default/jms-queue=testQueue/:add(entries=[\"queue/test\",\"java:jboss/exported/jms/queue/test\"])"
  fi
}

coreTestWithSpring() {
  setupJBossHome
  setupEnv
  ensureJavaExists
  stopJBoss
  deployCoreDistributionWithSpring
  removeJBossLogs
  startJBoss
  ensureRunningJBoss
  addTestQueue
  logMavenDependencies
  runTestsViaMavenWithSpring
  copyTestLogs
  stopJBoss
  copyJBossLogs
  detectFailures
}

coreTest() {
  setupJBossHome
  setupEnv
  ensureJavaExists
  stopJBoss
  deployCoreDistribution
  removeJBossLogs
  startJBoss
  ensureRunningJBoss
  logMavenDependencies
  runTestsViaMaven
  copyTestLogs
  stopJBoss
  copyJBossLogs
  detectFailures
}

binaryDistributionTestWithSpring() {
  setupJBossHome
  setupEnv
  ensureJavaExists
  stopJBoss
  deployBinaryDistributionWithSpring
  removeJBossLogs
  startJBoss
  ensureRunningJBoss
  addTestQueue
  runTestsViaAnt
  copyTestLogs
  stopJBoss
  copyJBossLogs
  detectFailures
}

binaryDistributionTest() {
  setupJBossHome
  setupEnv
  ensureJavaExists
  stopJBoss
  deployBinaryDistribution
  removeJBossLogs
  startJBoss
  ensureRunningJBoss
  runTestsViaAnt
  copyTestLogs
  stopJBoss
  copyJBossLogs
  detectFailures
}

sourceDistributionTestWithSpring() {
  setupJBossHome
  setupEnv
  ensureJavaExists
  stopJBoss
  deploySourceDistributionWithSpring
  removeJBossLogs
  startJBoss
  ensureRunningJBoss
  addTestQueue
  logMavenDependencies
  runTestsViaMavenWithSpring
  copyTestLogs
  stopJBoss
  copyJBossLogs
  detectFailures
}

sourceDistributionTest() {
  setupJBossHome
  setupEnv
  ensureJavaExists
  stopJBoss
  deploySourceDistribution
  removeJBossLogs
  startJBoss
  ensureRunningJBoss
  logMavenDependencies
  runTestsViaMaven
  copyTestLogs
  stopJBoss
  copyJBossLogs
  detectFailures
}
