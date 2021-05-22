%define __spec_install_post %{nil}
%define __os_install_post %{_dbpath}/brp-compress
%define debug_package %{nil}

Name: printerfacts
Summary: Printer facts: The API
Version: @@VERSION@@
Release: @@RELEASE@@%{?dist}
License: MIT
Group: Network
Source0: %{name}-%{version}.tar.gz
Requires(pre): /usr/sbin/useradd, /usr/bin/getent
Requires(postun): /usr/sbin/userdel
BuildRequires: systemd

BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root

%description
%{summary}

%pre
/usr/bin/getent passwd printerfacts || /usr/sbin/useradd -r -d /usr/bin/printerfacts -s /sbin/nologin printerfacts

#Upgrading
if [ $1 -eq 2 ]; then
    /usr/bin/systemctl stop %{name}.service >/dev/null 2>&1 ||:
fi

%post
if [ $1 -eq 1 ]; then        
    /usr/bin/systemctl daemon-reload
    /usr/bin/systemctl start %{name}.service
fi
if [ $1 -eq 2 ]; then
    /usr/bin/systemctl daemon-reload
    /usr/bin/systemctl start %{name}.service    
fi

%preun
#old package
#uninstall
if [ $1 -eq 0 ]; then
    /usr/bin/systemctl --no-reload disable %{name}.service
    /usr/bin/systemctl stop %{name}.service >/dev/null 2>&1 ||:
    /usr/bin/systemctl disable %{name}.service

fi
if [ $1 -eq 1 ]; then
    /usr/bin/systemctl --no-reload disable %{name}.service
    /usr/bin/systemctl stop %{name}.service
fi

%postun
/usr/sbin/userdel printerfacts

%prep
%setup -q

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a * %{buildroot}
mkdir -p %{buildroot}%{_unitdir}

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root,-)
%{_bindir}/*
/etc/default/printerfacts
/lib/systemd/system/printerfacts.service
