FROM amazonlinux:2017.12

RUN yum -y install yum-utils
RUN yum-config-manager --enable epel && yum -y update
RUN yum -y groupinstall 'Development Tools'
RUN yum -y install procps net-tools tree sudo man which bind-utils \
      mlocate python2-pip git xz jq dialog rsync ruby ruby-devel
RUN amazon-linux-extras install -y docker

RUN gem install ronn

RUN curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip \
  && (cd /tmp && unzip awscliv2.zip && ./aws/install)

RUN rpm -i http://www.ivarch.com/programs/rpms/pv-1.6.6-1.x86_64.rpm

RUN curl -L https://github.com/micha/json-table/raw/master/jt.tar.gz \
  |(cd /usr && tar xzvf -)

RUN curl https://git.savannah.gnu.org/cgit/parallel.git/plain/src/parallel > /usr/bin/parallel \
  && chmod 755 /usr/bin/parallel

RUN curl -L https://nodejs.org/dist/v12.19.0/node-v12.19.0-linux-x64.tar.xz \
  |unxz - |(cd /usr && tar --strip-components 1 -xf -)

ADD . /tmp/cfn-tools

RUN (cd /tmp/cfn-tools && git archive --format=tar HEAD root) \
  | (cd / && tar --strip-components=1 -xf -)

RUN npm install -g aws-sdk

RUN npm install -g /usr/src/template-package/

RUN find /usr/share/man -type f -name '*.ronn' -exec ronn -r {} \; && \
      find /usr/share/man -type f -name '*.ronn' -exec rm -f {} \;

WORKDIR /

CMD ["/bin/bash"]
