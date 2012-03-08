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
  # HACK if running cxf on AS71x, first install/update native
  if [ "$STACK_ID" = "cxf" ] && [[ $JBOSS_TARGET == jboss71* ]]; then
    echo "cxf stack with AS 71x, first installing native..."
    STACK_ID=native
    ORIG_STACK_DIR=$STACK_DIR
    STACK_DIR=$STACK_DIR/../../../NATIVE-BINDIST-AS-7.1.0-SUN-JDK-6/workspace/stack-native/
    setupEnv
    redeployBinaryDistribution
    STACK_ID=cxf
    STACK_DIR=$ORIG_STACK_DIR
  fi;
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
  $SCRIPTS_DIR/jboss.sh $JBOSS_HOME start $JBOSS_BIND_ADDRESS
}

copyJBossLogs() {
  cp $JBOSS_HOME/standalone/log/boot.log $WORKSPACE/jboss-boot.log
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
#  if [ -f $JBOSS_HOME/bin/run.sh ]; then
#    $SCRIPTS_DIR/http-spider.sh $JBOSS_BIND_ADDRESS:8080 $WORKSPACE
#    if [ -e $WORKSPACE/spider.failed ]; then
#      tail -n 100 $JBOSS_HOME/server/$JBOSS_CONFIG/log/server.log
#      stopJBoss
#      copyJBossLogs
#      exit 1
#    fi
#  else
#    echo "There's no admin console for AS7 yet"
    sleep 5
#  fi
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

coreTestWithSpring() {
  setupJBossHome
  setupEnv
  ensureJavaExists
  stopJBoss
  deployCoreDistributionWithSpring
  removeJBossLogs
  startJBoss
  ensureRunningJBoss
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
