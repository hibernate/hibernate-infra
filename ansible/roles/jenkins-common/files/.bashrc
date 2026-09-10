export JAVA_HOME=/usr/lib/jvm/java-openjdk
export LC_ALL=en_US.UTF-8

if [ -d "$HOME/bin" ]
then
	export PATH="$HOME/bin:$PATH"
fi

alias ll='ls -la'
