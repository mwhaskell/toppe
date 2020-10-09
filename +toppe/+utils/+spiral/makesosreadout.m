function [g,seq] = makesosreadout(fov, matrix, nLeafs, maxSlew, varargin)
% Make stack-of-spirals readout.mod file (fully sampled)
%
% function makesosreadout(fov, matrix, nLeafs, maxSlew, varargin)
%
% Inputs:
%   fov        [x y z] field-of-view (cm)
%   matrix     [nx ny nz] reconstructed image matrix size
%   nLeafs     number of spiral leafs 
%   maxSlew    Max slew rate for design (G/cm/ms)
% Options:
%   system     struct specifying hardware system limits, see systemspecs.m
%   maxGrad    Max gradient amplitude. Default: system.maxGrad
%   inout      'in' or 'out' (default) for spiral-in/out
%   ofname     output file name. Default: 'readout.mod'
%   rewDerate  derate slew during rewinder by this factor, to reduce PNS peak which seems to occur during rewinder. See pns.m.
% Outputs:
%   g          [nt 3]       [gx gy gz] gradients (G/cm)
%   seq        struct       design parameters; length of readout;  etc
%

import toppe.*
import toppe.utils.*
import toppe.utils.spiral.*
import toppe.utils.spiral.mintgrad.*

%% parse and check inputs
% Defaults
arg.system  = toppe.systemspecs();
arg.maxGrad = arg.system.maxGrad;
arg.inout   = 'out';
arg.ofname  = 'readout.mod';
arg.rewDerate = 0.8;

%arg = toppe.utils.vararg_pair(arg, varargin);
arg = vararg_pair(arg, varargin);

if fov(1) ~= fov(2)
	error('Anisotropic x/y FOV not supported.');
end
if matrix(1) ~= matrix(2)
	error('Anisotropic x/y matrix not supported.');
end

%% struct to be returned
seq.maxSlew = maxSlew;
seq.fov = fov;
seq.matrix = matrix;
seq.nLeafs = nLeafs;
seq.system = arg.system;

%% derate gradients so they pass hardware checks in checkwaveforms()
maxSlew = 0.999*maxSlew;    
maxGrad = 0.999*arg.system.maxGrad;

%% design spiral waveform (balanced)
npix = matrix(1);

doreverse= 0;
dovardens = 0;

rmax = npix/(2*fov(1));   % max k-space radius

% vds returns complex k, g
[k,g] = vds(maxSlew*1e3, maxGrad, arg.system.raster, nLeafs, fov(1), 0, 0, rmax);
cmd = sprintf('Created with Brian Hargreaves'' code: [k,g] = vds(%d,%d,4e-6,%d,fov,0,0,rmax);', maxSlew, maxGrad, nLeafs);

g = [0; 0; g(:)];  % add a couple of zeroes to make sure k=0 is sampled
nsamp = length(g);

% make balanced
gx = makebalanced(real(g(:)), 'maxSlew', arg.rewDerate*maxSlew/sqrt(2));  
gy = makebalanced(imag(g(:)), 'maxSlew', arg.rewDerate*maxSlew/sqrt(2));   

% make same length
n = max(length(gx), length(gy));
gx = [gx; zeros(n-length(gx), 1)];
gy = [gy; zeros(n-length(gy), 1)];

% partition (kz) encoding trapezoid
gzamp = (1/arg.system.raster)/(arg.system.gamma*fov(3));     % Gauss/cm
zarea = gzamp*matrix(3)*arg.system.raster;                   % Gauss/cm*sec
gpe = -trapwave2(zarea/2, maxGrad, maxSlew, arg.system.raster*1e3);

% put kz trapezoid and spiral together
gx1 = [0*gpe(:); zeros(2,1);   gx(:); 0*gpe(:)];
gy1 = [0*gpe(:); zeros(2,1);   gy(:); 0*gpe(:)];
gz1 = [  gpe(:); zeros(2,1); 0*gx(:);  -gpe(:)];

seq.sampWin = (length(gpe)+5):(length(gpe)+5+nsamp-1);

% spiral in or out 
if strcmp(arg.inout, 'in')
	gx = flipud(gx);
	gy = flipud(gy);
	seq.sampWin = fliplr(length(gx)-seq.sampWin);
end

% make sure duration is on 4-sample (16us) boundary
gx1 = toppe.utils.makeGElength(gx1);
gy1 = toppe.utils.makeGElength(gy1);
gz1 = toppe.utils.makeGElength(gz1);

% write to .mod file
writemod('gx', gx1, 'gy', gy1, 'gz', gz1, 'ofname', arg.ofname, 'desc', 'stack-of-spirals readout module', 'system', arg.system);

% return gradients for one leaf (to be rotated and kz-blipped in scanloop.txt)
g = [gx1 gy1 gz1];

return;







if dovardens
	type = 'vds';
else
	type = 'unif';
end
if doreverse
	g = flipdim(g,1);  % reverse spiral 
	fname = sprintf('g-reverse-%s-nl%d-fov%d-npix%d-%s.mod', type, nLeafs, fov, npix, date);
else
	fname = sprintf('g-%s-nl%d-fov%d-npix%d.mod', type, nLeafs, fov(1), npix);
end
fprintf(1,'gradient duration is %.2f ms \n', 4e-3*length(g));
desc = sprintf('spiral readout .mod file for toppe\n%s\n',cmd);
%toppe.writemod('gx', gx, 'gy', gy, 'ofname', fname, 'desc', desc);

%Combines spiral readout and z phase-encode blips.

% readout for second DESS echo (spiral-in)
gx2 = flipud(gx1);
gy2 = flipud(gy1);
gz2 = flipud(gz1);

% write to readout.mod and plot
gx = [gx1, gx2];
gy = [gy1, gy2];
gz = [gz1, gz2];
gx = makeGElength(gx);   % make divisible by 4
gy = makeGElength(gy);
gz = makeGElength(gz);
rhfrsize = size(gx, 1);
%mat2mod(0.01*ones(size(gx)),0*gx,gx,gy,gz,90,'readout.mod','1mm isotropic DESS stack-of-spirals readout',0, [0 rhfrsize], false);
writemod('gx', gx, 'gy', gy, 'gz', gz, 'ofname', 'readout.mod', 'desc', 'DESS stack-of-spirals readout');
T = 4e-3*[0.5:1:rhfrsize];
figure; plot(T,gx,'r'); hold on; plot(T,gy,'g'); plot(T,gz,'b');
xlabel('time (msec)'); ylabel('G/cm');



%% create scan,dess,spiral.tgz
writeloop;

fprintf(1,'\n\tcreate tar archive...');
system('./tarit');
fprintf(1,'\tdone\n');

fprintf(1,'Calculating sequence for display...');
d = readloop('scanloop.txt');
plotseq(800, 820, 'loopArr', d);
%system(sprintf('cp scan.tgz scan_te%dms_tr%.1fs.tgz',round(TE/1e3),TR/1e6)');
fprintf(1,'\n\tdone\n');

fprintf('Next step: Copy scan,dess,spiral.tgz to /usr/g/bin/ and extract, then scan with toppev2\n');


