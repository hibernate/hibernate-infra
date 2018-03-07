export JAVA_HOME=/usr/lib/jvm/java-openjdk
export M2_HOME=/home/jenkins/apache-maven-{{ maven_version }}
export M2=$M2_HOME/bin
export PATH=$M2:$HOME/bin:$PATH
export LC_ALL=en_US.UTF-8

alias ll='ls -la'
