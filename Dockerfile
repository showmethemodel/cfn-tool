FROM amazonlinux:2017.12

RUN yum -y install yum-utils
RUN yum-config-manager --enable epel && yum -y update
RUN yum -y groupinstall 'Development Tools'
RUN yum -y install procps net-tools tree sudo man which \
      mlocate python2-pip git xz jq dialog rsync
RUN amazon-linux-extras install -y docker

RUN pip install awscli==1.15.48
RUN pip uninstall -y pyyaml
RUN pip install pyyaml==4.2b4

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

RUN npm install -g /usr/src/template-package/

WORKDIR /

CMD ["/bin/bash"]
